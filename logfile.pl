#!/usr/bin/perl

# =====
# Author: Karl-Heinz Fischbach
# Date: 26.8.2023
# Content: tail logfiles, filtered by regex rules and lines not filtered sent to TELEGRAM channel.
# 
# Copyright (C) 2023  Karl-Heinz Fischbach
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program; if not, see <http://www.gnu.org/licenses/>.
#
# Example how to call the script:
# Remember: --bot is a mandatory parameters
# /usr/bin/perl ~/scripts/av_logfile.pl -l -v 4 --logfile /var/log/syslog --bot '<TELEGRAM BOT String>'
# /usr/bin/perl ~/scripts/av_logfile.pl -l --logfile /var/log/syslog --logfile /var/log/auth.log --bot '<TELEGRAM BOT String>'
# in case you need to run tests:
# /usr/bin/perl -d ~/logfile.pl -t -l -v 5 --logfile /var/log/syslog --bot '<TELEGRAM BOT token>'
# 
# Changelog: 
# 
# =====
# 20250113; regex replace does not work. String::Substitution implemented. See: https://stackoverflow.com/questions/63515762/perl-use-backreferences-in-a-replacement-string-variable
# 20250112; structure of configuration files changed to allow modification of logfile messages for print on TELEGRAM
# 20231018; File as an optional or additional output besides TELEGRAM added;
# this includes to have additional commandline parameters

use local::lib; # this will allow a local perl lib

use strict;
use warnings;
use utf8;
use POSIX;
use Switch;

use Net::Domain qw(hostname hostfqdn hostdomain domainname);

use Getopt::Long qw(:config no_ignore_case);
use autodie; # die if problem reading or writing a file
use Sys::Hostname;

use String::Substitution qw( sub_copy );

use WWW::Telegram::BotAPI;

use DateTime;

use File::Spec;
use File::Basename;
use File::Touch;
use File::ReadBackwards;
use File::Tail;
use File::Modified;
use IO::All;
use IO::Handle;
use Config::IniFiles;

use Log::Log4perl qw(get_logger);
use Log::Log4perl::Config;
use Log::Log4perl::Level;
use Log::Dispatch;

#  _      __        _       _     _      
#   \    / /       (_)     | |   | |     
#  \ \  / /_ _ _ __ _  __ _| |__ | | ___ 
#   \ \/ / _` | '__| |/ _` | '_ \| |/ _ \
#    \  / (_| | |  | | (_| | |_) | |  __/
#     \/ \__,_|_|  |_|\__,_|_.__/|_|\___|
#                                        
#                                        
my $av_std_BASENAME=basename($0,".pl");
my $av_std_DIRNAME=dirname($0);
my $av_std_EXIT=0;
my $av_std_RETVAL;
my $av_std_TMP='/tmp';
my $av_std_LOG4PERLCONF="$av_std_DIRNAME/av_log4perl.conf";
my $av_std_VERBOSE=4;
# Loglevel = 0; no logging
# Loglevel = 1; fatal
# Loglevel = 2; error
# Loglevel = 3; warn
# Loglevel = 4; info
# Loglevel = 5; debug
# Loglevel = 6; trace

our $av_std_LOGFILE="$av_std_TMP/job_" . $av_std_BASENAME . ".log";
my $av_std_LOGGING=0;
my $av_std_TEST=0;

my $av_fn_REGEX=undef;
my $av_fn_OUTFILE=undef;
my $av_fn_INIFILE="$av_std_DIRNAME/av_logfile.ini"; # this is the STANDARD, but this will probably be changed by commandline options.

my $av_loc_BLOCK="";
my $av_loc_tgram_CHATID=""; # this is Chat-ID of the Telegram Channel
my $av_loc_tgram_BOT=undef;
my $av_loc_INDEX;
my $av_loc_EPOCH=DateTime->now( time_zone=>'Europe/Berlin', locale=>'de-DE' )->epoch();

###
### FILEHANDLE
###
my $av_fh_FILE=undef;
my $av_fh_OUTFILE=undef;

###
### predefined objects
###
my $av_obj_DT=DateTime->now( time_zone=>'Europe/Berlin', locale=>'de-DE' );
my $av_obj_LOGGER=undef;
my $av_obj_TMP=undef;
my $av_obj_FILE=undef;
my $av_obj_REGEXFILE=undef;
my $av_obj_TAIL=undef;
my $av_obj_INIFILE=undef;
my $av_obj_TGRAM=undef;
my $av_obj_TGERROR=undef;

###
### for various use
###
my $av_tmp_CURRLINE="";
my $av_tmp_DELETED=0;
my $av_tmp_DIR="/tmp";
my $av_tmp_FN;
my $av_tmp_LINE;
my $av_tmp_NUMBERFOUND=undef;
my $av_tmp_OLDLINE="";
my $av_tmp_PATTERN="";
my $av_tmp_REPLACE="";
my $av_tmp_REGEXBLOCK=undef;
my $av_tmp_STRING;
my $av_tmp_TIMELEFT=undef;
my $av_tmp_logger_CONF="";

###
### Arrays
###
my @av_arr_CHANGES;
my @av_arr_LOG4PERLCONF;
my @av_arr_LOGFILES;
my @av_arr_PENDING;
my @av_arr_INCLUDES=();
my @av_arr_STRING;
my @av_arr_TAIL;
my @av_arr_LINE;

###
### Hashes
###
my %av_ha_MATRIX=(); # contains an HASHES OF ARRAYS - see: https://perldoc.perl.org/perldsc#HASHES-OF-ARRAYS
my %av_ha_TGERROR=(); # contains an HASHES OF ARRAYS - see: https://perldoc.perl.org/perldsc#HASHES-OF-ARRAYS

#  ______                _   _                 
#    ____|              | | (_)                
#   |__ _   _ _ __   ___| |_ _  ___  _ __  ___ 
#    __| | | | '_ \ / __| __| |/ _ \| '_ \/ __|
#   |  | |_| | | | | (__| |_| | (_) | | | \__ \
#  _|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
#                                              
#                                              
### functions commands block
$av_loc_BLOCK="Functions";

sub av_help
{
  print "Usage of script:" . "\n";
  print "xxx.pl [-h, --help] [-t, --test] [-l, --logging] [-v [0-6], --verbose [0-6]] -b, --bot <bot token> [-f, --logfile <logfile path>] [-i, --ini=<filename>] [-r, --regex=<filename>] [--chatid <Chat ID>] [-o, --output-file]" . "\n";
  print "what the options mean:" . "\n";
  print "  -h, --help := this information" . "\n";
  print "  -t, --test (optional):= test mode on; This will imply to fetch some file from a temporary directory" . "\n";
  print "  -l, --logging (optional):= log all output to file given" . "\n";
  print "  -v [0-6], --verbose [0-6] (optional):= verbose logging of the script, Default: 4" . "\n";
  print "  -b, --bot (mandatory):= TELEGRAM Bot Token; if set, all logfile messages will be sent to the TELEGRAM Chat/Channel" . "\n";
  print "  -f, --logfile (optional):= logfile to process. Option can occur several times. Normally the list of files comes from the ini-file" . "\n";
  print "  -i, --ini (optional):= ini-file to use" . "\n";
  print "  -r, --regex (optional):= regex-file to use" . "\n";
  print "      --chatid (optional):= TELEGRAM Channel-ID. Normally this comes from the ini-file" . "\n";
  print "  -o, --output-file (optional):= file to send output to instead to send it to a TELEGRAM Chat/Channel" . "\n";
}

sub av_regexfile_read 
{
  my $av_sub_FH;
  my $av_loc_INDEX;
  $av_tmp_FN = $_[0]; # .conf-file to process
  
  $av_obj_LOGGER->debug("file to open: $av_tmp_FN");
  
  if (-e $av_tmp_FN) # check if .conf-file exists
  {
    open($av_sub_FH, "<", $av_tmp_FN)
      or die $av_obj_LOGGER->error("fehler bei open von $av_tmp_FN: $!");
    
    while($av_tmp_LINE = readline($av_sub_FH)) # read all lines from .conf-file
    { 
      $av_obj_LOGGER->trace("debug \$av_tmp_LINE: $av_tmp_LINE");
      
      if ( substr($av_tmp_LINE,0,1) eq "#" ) # if it is a comment, ignore
      {
        next;
      }
      if ( length($av_tmp_LINE) <=1 ) # if the line is empty, ignore
      {
        next;
      }
      if ( $av_tmp_LINE =~ /^include\s+(\S+)/ ) # if the line contains an include-statement, perform recursive processing
      {
        $av_tmp_STRING = $1; # $1 contains the filename
        push(@av_arr_INCLUDES,$av_tmp_STRING); # this is an arrray containing all conf-files included. Reason: all these file must get checked if changes are made
        if ( $av_std_TEST )
        {
          $av_tmp_STRING = "$av_tmp_DIR/$av_tmp_STRING"; # if it is a test the file should come from the directory defined in $av_tmp_DIR
        }
        av_regexfile_read($av_tmp_STRING); # calling the same subroutine
        next; # the include-statement is performed, next line must be read
      }
      if ( $av_tmp_LINE =~ m/^\[(.*)\]/ ) # if it is a line starting a group [<logfile filename>] 
      {
        $av_tmp_REGEXBLOCK = $1; # $1 now contains the logfile where the regex line belong to
        $av_ha_MATRIX{$av_tmp_REGEXBLOCK} = [ ]; # now the group name (the logfile name) needs to get stored in the fist element of the Hash - but empty for now
        next; # statement is process, go to next line
      }
      ### check if line is still of old structure
      if ( $av_tmp_LINE !~ /^(.;|..;)/ )
      {
        $av_tmp_LINE = substr($av_tmp_LINE,0,1) . ";" . substr($av_tmp_LINE,1);
        $av_obj_LOGGER->trace("debug old line modified");
      }
      # this is now a line with regex expressions. Needs to get stored in the Hash, assigned to the current group
      chomp($av_tmp_LINE); # eliminate NL/CR
      $av_loc_INDEX = $av_ha_MATRIX{$av_tmp_REGEXBLOCK}->$#*; # max number of elements in array of group
      $av_loc_INDEX++; # next array position
      $av_ha_MATRIX{$av_tmp_REGEXBLOCK}[$av_loc_INDEX] = $av_tmp_LINE; # regex line gets stored into array
    }
    close($av_sub_FH);
  }
}

sub av_inifile_read
{
  @av_arr_TAIL=();
  
  $av_obj_INIFILE = Config::IniFiles->new( -file => "$av_fn_INIFILE" )
      or die "Block: $av_loc_BLOCK; Can't open < $av_fn_INIFILE: $!";
  
  @av_arr_STRING=();
  @av_arr_STRING = $av_obj_INIFILE->Parameters('LOGFILES'); # here you get an array of all keys of group LOGFILES, only the KEYs, not the VALUEs
  
  if ( not @av_arr_LOGFILES )
  {
    @av_arr_LOGFILES=();
    foreach  my $elem1 (@av_arr_STRING) # now all Values of the identified Keys will get read
    {
      push (@av_arr_LOGFILES, $av_obj_INIFILE->val('LOGFILES', $elem1)); # store values in array
      
      $av_obj_LOGGER->info("Block: $av_loc_BLOCK; " . $av_obj_INIFILE->val('LOGFILES', $elem1)); # debug
    }
  }

  if ($av_std_TEST)
  {
    @av_arr_LOGFILES=('/var/log/syslog', '/var/log/auth.log'); # in case of TEST focus on these logfiles only
    
    $av_tmp_DIR = $av_obj_INIFILE->val('TEST', 'tmp', '/tmp'); # Directory
    $av_loc_tgram_CHATID = $av_obj_INIFILE->val('TEST', 'chatid'); # TELEGRAM Channel-ID
    if ( ! defined $av_fn_REGEX ) # there might be some regex conf-file given by commandline options. If so, this has preference.
    {
      $av_fn_REGEX = $av_obj_INIFILE->val('TEST', 'regex', '~/scripts/av_logfile_regex.conf'); # Regex File
    }
  }
  else 
  {
    $av_tmp_DIR = $av_obj_INIFILE->val('PARAMS', 'tmp', '/tmp'); # Directory
    $av_loc_tgram_CHATID = $av_obj_INIFILE->val('PARAMS', 'chatid'); # TELEGRAM Channel-ID
    if ( ! defined $av_fn_REGEX ) # there might be some regex conf-file given by commandline options. If so, this has preference.
    {
      $av_fn_REGEX = $av_obj_INIFILE->val('PARAMS', 'regex', '~/scripts/av_logfile_regex.conf'); # Regex File
    }
  }
  # fill array with tail-objects
  foreach ( @av_arr_LOGFILES ) {
      push( @av_arr_TAIL, File::Tail->new(name=>"$_",debug=>0,ignore_nonexistant=>1,reset_tail=>0) );
  }
}
#  _____                                _   _             
#    __ \                              | | (_)            
#   |__) | __ ___ _ __   __ _ _ __ __ _| |_ _  ___  _ __  
#    ___/ '__/ _ \ '_ \ / _` | '__/ _` | __| |/ _ \| '_ \ 
#   |   | | |  __/ |_) | (_| | | | (_| | |_| | (_) | | | |
#  _|   |_|  \___| .__/ \__,_|_|  \__,_|\__|_|\___/|_| |_|
#                | |                                      
#                |_|                                      
### preparation commands block
$av_loc_BLOCK="Preparation";

print "all options: @ARGV\n";

GetOptions (
"h|help"           => \&av_help,                                                 # help
"t|test"           => \$av_std_TEST,                                             # test
"l|logging"        => \$av_std_LOGGING,                                          # logging
"v|verbose:4"      => \$av_std_VERBOSE,                                          # verbose + loglevel
"b|bot=s"          => \$av_loc_tgram_BOT,                                        # Telegram BOT Token
"chatid=s"         => \$av_loc_tgram_CHATID,                                     # Telegram Channel
"i|ini=s"          => \$av_fn_INIFILE,                                           # ini-file
"f|logfile=s"      => \@av_arr_LOGFILES,                                         # Logfiles to process
"o|output-file=s"  => \$av_fn_OUTFILE,                                           # Output to file
"r|regex=s"        => \$av_fn_REGEX,                                             # logfile to use
);

###
### processing GetOptions Parameters
###
if ( $av_std_LOGGING && ! defined $av_std_LOGFILE )
{
  print "no logfile path given" . "\n";
  exit(1);
}

# preparing Log4perl configured to log on screen and logfile. STANDARD configuration file: av_log4perl.conf
if ( $av_std_LOGGING )
{
  if ( -e $av_std_LOG4PERLCONF ) # if log4perl configuration file exists - if not, use some standards
  {
    # create logfile specified
    $av_obj_FILE = File::Touch->new()->touch("$av_std_LOGFILE"); # create the logfile specified on commandline options
  
    # Datei einlesen
    open($av_fh_FILE, "<", "$av_std_LOG4PERLCONF") 
      or die "Couldn't open file $av_std_LOG4PERLCONF, $!";

    while( readline($av_fh_FILE) ) 
    {
      chomp($_); # Zeilenende entfernen
      push(@av_arr_LOG4PERLCONF, $_); # in array speichern
    }
    close($av_fh_FILE);

    # array in scalar (string) umwandeln
    $_=join( "\n", @av_arr_LOG4PERLCONF );
    #
    Log::Log4perl::Config->utf8( 1 );
    Log::Log4perl->init( \$_ );
    $av_obj_LOGGER = get_logger();
  }
  # if the log4perl configuration file does not exist, use some minimal standards
  else {
    Log::Log4perl::Config->utf8( 1 );
    Log::Log4perl->easy_init($ERROR);
    $av_obj_LOGGER = get_logger();
  }
}
# if no logging is required via commandline option use some minimal standards
else {
  Log::Log4perl::Config->utf8( 1 );
  Log::Log4perl->easy_init($ERROR);
  $av_obj_LOGGER = get_logger();
}

# There are six predefined log levels: FATAL, ERROR, WARN, INFO, DEBUG, and TRACE (in descending priority).
# this now sets the loglevel based on the commandline option if set or the default
switch ( $av_std_VERBOSE )
{
  case 0 { $av_obj_LOGGER->level("$OFF") }
  case 1 { $av_obj_LOGGER->level("$FATAL") }
  case 2 { $av_obj_LOGGER->level("$ERROR") }
  case 3 { $av_obj_LOGGER->level("$WARN") }
  case 4 { $av_obj_LOGGER->level("$INFO") }
  case 5 { $av_obj_LOGGER->level("$DEBUG") }
  else { $av_obj_LOGGER->level("$ALL") }
}

if ( Log::Log4perl->initialized() ) # check if correctly initialized
{
  $av_obj_LOGGER->info("Block: $av_loc_BLOCK - Log::Log4perl seems to be initialized");
}
else {
  print "Block: $av_loc_BLOCK - Log::Log4perl seems not to be initialized";
  exit ($av_std_EXIT);
}

$av_obj_LOGGER->debug( "started" ); # debug

# write pid to file to be able to kill process
open($av_fh_FILE, ">./av_logfile.pid");
print $av_fh_FILE $$;
close($av_fh_FILE);

###
### chech if TEST - and change some values of variables
###
if ( $av_std_TEST ) # only if not test set the PID into the PID-File
{
  if ( -e "$av_tmp_DIR/av_logfile.ini" )
  {
    $av_fn_INIFILE="$av_tmp_DIR/av_logfile.ini";
  }
}

###
### ini-File einlesen
###
if ( -e $av_fn_INIFILE )
{
  av_inifile_read();
}
else 
{
  print "Block: $av_loc_BLOCK - INI-File does not exist";
  exit ($av_std_EXIT);
}


if ( $av_std_TEST ) # if TEST, get the regex-file from some temporary directory
{
  $av_fn_REGEX="$av_tmp_DIR/av_logfile_regex.conf";
}

###
### check on output-file
###
if ( defined $av_fn_OUTFILE )
{
  # create output-file specified
  File::Touch->new()->touch("$av_fn_OUTFILE"); # create the output-file specified on commandline options

  open($av_fh_OUTFILE, ">>:encoding(UTF-8)", "$av_fn_OUTFILE") 
    or die "Couldn't open file $av_fn_OUTFILE, $!";
  $av_fh_OUTFILE->autoflush;
}

###
### regex-conf einlesen
###

%av_ha_MATRIX=();
@av_arr_INCLUDES=();
push(@av_arr_INCLUDES,$av_fn_REGEX);
av_regexfile_read($av_fn_REGEX);

$av_obj_REGEXFILE = File::Modified->new(files=>\@av_arr_INCLUDES); # create the object to check if the regexfile gets modified

$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_BASENAME: $av_std_BASENAME\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_DIRNAME: $av_std_DIRNAME\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_LOGGING: $av_std_LOGGING\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_LOGFILE: $av_std_LOGFILE\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_loc_tgram_BOT: $av_loc_tgram_BOT\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_TEST: $av_std_TEST\n") if ( defined $av_std_TEST ); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_VERBOSE: $av_std_VERBOSE\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_fn_REGEX: $av_fn_REGEX\n") if ( defined $av_fn_REGEX ); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \@av_arr_LOGFILES: @av_arr_LOGFILES\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_fn_OUTFILE: $av_fn_OUTFILE\n") if ( defined $av_fn_OUTFILE ); # debug

###
### prepare Telegram Object
###

if ( defined $av_loc_tgram_BOT )
{
  $av_obj_TGRAM = WWW::Telegram::BotAPI->new(
   token => "$av_loc_tgram_BOT"
  );
}

#  __  __       _         _____                  
#    \/  |     (_)       |  __ \                 
#   \  / | __ _ _ _ __   | |__) | __ ___   ___   
#   |\/| |/ _` | | '_ \  |  ___/ '__/ _ \ / __|  
#   |  | | (_| | | | | | | |   | | | (_) | (__ _ 
#  _|  |_|\__,_|_|_| |_| |_|   |_|  \___/ \___(_)
#                                                
#                                                
$av_loc_BLOCK="Main Processing";
$av_obj_LOGGER->info("Block: $av_loc_BLOCK - started");

$av_obj_LOGGER->trace("\@av_arr_TAIL: @av_arr_TAIL"); # debug

# Start message to Output - only to TELEGRAM, not to output-file
if ( $av_loc_tgram_BOT )
{
  if ( $av_std_TEST ) # if TEST, the message is different
  {
    unless ( eval
    {
      $av_obj_TGRAM->sendMessage (
        {
            chat_id => $av_loc_tgram_CHATID,
            text    => hostname() . " " . basename($0) . " " . "TEST started",
            disable_notification => 'true',
            parse_mode => 'HTML',
        }
      )
    } )
    {
      my $av_obj_TGERROR = $av_obj_TGRAM->parse_error;
      $av_obj_LOGGER->error("TELEGRAM Error: $av_obj_TGERROR->{msg}; Error Type: $av_obj_TGERROR->{type}"); # debug
      die 'TELEGRAM sendMessage error!';
    }
  }
}
if ( defined $av_fn_OUTFILE ) # write to file
{
  if ( $av_std_TEST ) # if TEST, the message is different
  {
    $av_tmp_STRING = $av_obj_DT->ymd . " " . $av_obj_DT->hms . " " . hostname() . " " . "### Start in Testmode ###\n";
    print $av_fh_OUTFILE $av_tmp_STRING;
  }
  $av_tmp_STRING = $av_obj_DT->ymd . " " . $av_obj_DT->hms . " " . hostname() . " " . "### Start ###\n";
  print $av_fh_OUTFILE $av_tmp_STRING;
}

while (1)
{
  # this block allows to check if the regex.conf file has changed meanwhile. Then it will get reloaded. 
  # So you can make changes to the regex.conf file while script is running!
  $av_loc_BLOCK="Check on changed regex.conf file";
  @av_arr_CHANGES = ();
  @av_arr_CHANGES = $av_obj_REGEXFILE->changed;
  if (@av_arr_CHANGES)
  {
    $av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \@av_arr_CHANGES: @av_arr_CHANGES"); # debug

    %av_ha_MATRIX=();
    @av_arr_INCLUDES=();
    push(@av_arr_INCLUDES,$av_fn_REGEX);
    av_regexfile_read($av_fn_REGEX);
    $av_obj_REGEXFILE->update();
    
    $av_obj_LOGGER->info("Block: $av_loc_BLOCK - $av_fn_REGEX changed; read again!"); # debug

    # message only to telegram - not to output-file
    if ( $av_loc_tgram_BOT )
    {
      unless ( eval
      {
        $av_obj_TGRAM->sendMessage (
          {
              chat_id => $av_loc_tgram_CHATID,
              text    => hostname() . " " . "$av_fn_REGEX changed; read again!",
              disable_notification => 'true',
              parse_mode => 'HTML',
          }
        )
      } )
      {
        my $av_obj_TGERROR = $av_obj_TGRAM->parse_error;
        $av_obj_LOGGER->error("TELEGRAM Error: $av_obj_TGERROR->{msg}; Error Type: $av_obj_TGERROR->{type}"); # debug
        die 'TELEGRAM sendMessage error!';
      }
    }
  }
  
  $av_loc_BLOCK="Tail";
  # hier werden die letzten zeilen aus den logfiles gelesen bzw. geprüft, ob zeilen vorliegen
  # in @av_arr_PENDING werden dann die logfiles gespeichert wo es neue zeilen gibt
  $av_tmp_NUMBERFOUND=0;
  $av_tmp_TIMELEFT=0;
  @av_arr_PENDING=();
  ($av_tmp_NUMBERFOUND,$av_tmp_TIMELEFT,@av_arr_PENDING)=File::Tail::select(undef,undef,undef,60,@av_arr_TAIL);
  
  #hier werden die logfiles die neue zeilen haben abgearbeitet
  unless ($av_tmp_NUMBERFOUND) 
  {
    # timeout - do something else here, if you need to
  } 
  else 
  {
    foreach $av_obj_TMP (@av_arr_PENDING)
    {
      # zeile von logfile lesen
      $av_tmp_LINE=$av_obj_TMP->read;
      
      # alle zeilen in der parameterdatei lesen und die zeile aus dem logfile gegen den regex prüfen
      $av_loc_BLOCK="regex matching";
      foreach my $i ( 0 .. $av_ha_MATRIX{$av_obj_TMP->{input}}->$#* )
      {
        my $line = $av_ha_MATRIX{$av_obj_TMP->{input}}[$i];
        $av_tmp_DELETED=0;
        $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - logfile: $av_obj_TMP->{input} - \$line: $line");
        $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - regex: $av_ha_MATRIX{$av_obj_TMP->{input}}[$i]");
        
        # hier müsste der String aufbereitet werden
        # aufbau der zeile:
        # trennzeichen: ;
        # block1: -|+m|s;
        # block2: suchbegriff (regex);
        # block3: ersetzt durch (regex)
        @av_arr_LINE = ();
        @av_arr_LINE = split(';', $line);
        
        # if there is no delimiter in the line (e.g. old line not changed)
        if ( scalar @av_arr_LINE == 1 )
        {
          $av_obj_LOGGER->error("Block: $av_loc_BLOCK - line seems incomplete");
          next;
        }
        else 
        {
          # block1:
          # - (only) is old format
          # -m just to ignore the line if search pattern matches
          # -s should not be present since if ignoring the line a substitute does not make sense
          if ( $av_arr_LINE[0] eq "-" || $av_arr_LINE[0] eq "-m" || $av_arr_LINE[0] eq "-s" )
          {
            $av_tmp_PATTERN = $av_arr_LINE[1];
            if ( $av_tmp_LINE =~ /$av_tmp_PATTERN/ )
            {
              $av_tmp_DELETED=1;
              $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - line deleted from " . $av_obj_TMP->{input} . "!");
              last;
            }
          }
          # block1:
          # print line if search pattern matches
          if ( $av_arr_LINE[0] eq "+" || $av_arr_LINE[0] eq "+m" )
          {
            $av_tmp_PATTERN = $av_arr_LINE[1];
            if ( $av_tmp_LINE =~ /$av_tmp_PATTERN/ )
            {
              $av_tmp_DELETED=0;
              $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - line printed from " . $av_obj_TMP->{input} . "!");
              last;
            }
          }
          # block1:
          # print line if search pattern matches; output will be replaced by replace pattern
          if ( $av_arr_LINE[0] eq "+s" )
          {
            $av_tmp_PATTERN = $av_arr_LINE[1];
            $av_tmp_REPLACE = $av_arr_LINE[2];
            if ( $av_tmp_LINE =~ /$av_tmp_PATTERN/ )
            {
              $av_tmp_LINE = sub_copy( $av_tmp_LINE, $av_tmp_PATTERN, $av_tmp_REPLACE );
              $av_tmp_DELETED=0;
              $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - line printed from " . $av_obj_TMP->{input} . "!");
              last;
            }
          }
        }
      }
      if ( ! $av_tmp_DELETED && length($av_tmp_LINE) > 1 )
      {
        $av_loc_BLOCK="TELEGRAM";
        $av_obj_LOGGER->debug("Block: $av_loc_BLOCK - will get sent: $av_tmp_LINE");
        $av_tmp_LINE =~ s/<|>//g;
        $av_tmp_STRING = hostname() . " " . "Logfile: " . "<strong>" . $av_obj_TMP->{input} . "</strong>" . " " . $av_tmp_LINE;

        # write line to TELEGRAM Channel - if
        if ( $av_loc_tgram_BOT )
        {
          if ( DateTime->now( time_zone=>'Europe/Berlin', locale=>'de-DE' )->epoch() ge $av_loc_EPOCH )
          {
            unless ( eval 
            {
              $av_obj_TGRAM->sendMessage 
              (
                {
                  chat_id => $av_loc_tgram_CHATID,
                  text    => $av_tmp_STRING,
                  disable_notification => 'true',
                  parse_mode => 'HTML',
                }
              )
            } )
            {
              my $av_obj_TGERROR = $av_obj_TGRAM->parse_error;
              $av_obj_LOGGER->error("TELEGRAM $av_obj_TGERROR->{msg}; Error Type: $av_obj_TGERROR->{type}"); # debug
              $av_obj_TGERROR->{msg} =~ m/(\d{1,3})/;
              $av_obj_LOGGER->error("TELEGRAM Error: we have to go sleeping for $1 seconds"); # debug
              $av_loc_EPOCH += $1;
            }
          }
        }
        # write line to output file - if
        if ( defined $av_fn_OUTFILE )
        {
          $av_tmp_STRING = $av_obj_DT->ymd . " " . $av_obj_DT->hms . " " . hostname() . " " . "Logfile: " . $av_obj_TMP->{input} . " " . $av_tmp_LINE;
          print $av_fh_OUTFILE $av_tmp_STRING;
        }
        
        # check for double lines
        $av_tmp_CURRLINE = $av_tmp_LINE;
        # we strip all elements from the line which might be variable (like date/time or process-id)
        $av_tmp_CURRLINE =~ s/^\S{3} \d{1,2} \d{2}:\d{2}:\d{2} //;
        $av_tmp_CURRLINE =~ s/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3} \- \- \[.*\d{4}\] //;
        $av_tmp_CURRLINE =~ s/^\S{3}, \d{4}\-\d{1,2}\-\d{1,2}, \d{1,2}:\d{1,2}:\d{1,2} \d{1,2}//;
        $av_tmp_CURRLINE =~ s/^\d{4}\-\d{1,2}\-\d{1,2}, \d{1,2}:\d{1,2}:\d{1,2}, \d{1,5}//;
        $av_tmp_CURRLINE =~ s/\[\d{1,}\] //;
        $av_tmp_CURRLINE =~ s/\[pid \d{1,}\] //;
        if ( $av_tmp_CURRLINE eq $av_tmp_OLDLINE )
        {
          $av_tmp_DELETED=1;
          $av_obj_LOGGER->info("Block: $av_loc_BLOCK - double line: $av_tmp_OLDLINE");
        }
        else
        {
          $av_tmp_OLDLINE = $av_tmp_CURRLINE;
          $av_obj_LOGGER->debug("Block: $av_loc_BLOCK - backup pure line: $av_tmp_OLDLINE");
        }
      }
      $av_tmp_DELETED=0;
    }
  }
}
close($av_fh_OUTFILE);

#  ______           _   _____                  
# |  ____|         | | |  __ \                 
# | |__   _ __   __| | | |__) | __ ___   ___   
# |  __| | '_ \ / _` | |  ___/ '__/ _ \ / __|  
# | |____| | | | (_| | | |   | | | (_) | (__ _ 
# |______|_| |_|\__,_| |_|   |_|  \___/ \___(_)
#                                              
#                                              
### end procedure
$av_loc_BLOCK="End Processing";
$av_obj_LOGGER->info("Block: $av_loc_BLOCK - ended");
exit (0);
