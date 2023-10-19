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
# Remember: --logfile and --bot are mandatory parameters
# /usr/bin/perl ~/scripts/av_logfile.pl -l -v 4 --logfile <directory>/job_logfile.log --bot '<TELEGRAM BOT String>'
# /usr/bin/perl ~/scripts/av_logfile.pl -l --logfile <directory>/job_logfile.log --bot '<TELEGRAM BOT String>'
# in case you need to run tests:
# /usr/bin/perl -d ~/logfile.pl -t -l -v 5 --logfile <directory>/job_logfile.log --bot '<TELEGRAM BOT token>'
# /usr/bin/perl -d ~/logfile.pl -t -l -v 5 --logfile <directory>/job_logfile.log
# 
# Changelog: 
# 
# =====
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

my $av_loc_BLOCK="";
my $av_loc_CONFIG; # Bolean, if a config file has been given at the command line
my $av_loc_REGEXFILE="";
my $av_loc_INIFILE="$av_std_DIRNAME/av_logfile.ini"; # this is the STANDARD, but this will probably be changed by commandline options.
my $av_loc_TELEGRAM=1; # use TELEGRAM or not; Default: true
my $av_loc_tgram_CHATID=""; # this is Chat-ID of the Telegram Channel
my $av_loc_tgram_BOT=undef;
my $av_loc_INDEX;
my $av_loc_OUTPUT=0; # print lines found to File; Default: false
my $av_loc_OUTFILE=undef; # if filename of Output File has been given via commandline parameter, lines will get written to the file
my $av_loc_EPOCH=DateTime->now( time_zone=>'Europe/Berlin', locale=>'de-DE' )->epoch();

###
### FILEHANDLE
###
my $av_fh_FILE;
my $av_fh_OUTFILE;

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
my $av_obj_OUTFILE=undef;

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
my @av_arr_PENDING=undef;
my @av_arr_INCLUDES=();
my @av_arr_STRING;
my @av_arr_TAIL;

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
  print "xxx.pl [-b, --bot <bot token>] [-h, --help] [-f, --logfiles] [-l, --logging] [-t, --test] [-c, --config=<filename>] [-r, --regex=<filename>] [--chatid <Chat ID>] [-o, --output-file] [-v [0-6], --verbose [0-6]]" . "\n";
  print "what the options mean:" . "\n";
  print "--bot := TELEGRAM Bot Token, mandatory" . "\n";
  print "  -h, --help := this information" . "\n";
  print "  -f, --logfiles := logfiles to process, comma separated list. Normally the list of files comes from the ini-file" . "\n";
  print "  -l, --logging := log all output to file defiled by --logfile" . "\n";
  print "  -t, --test := test mode on" . "\n";
  print "  -c, --config := ini-file to use" . "\n";
  print "  -r, --regex := regex-file to use" . "\n";
  print "--chatid := TELEGRAM Channel-ID. Normally this comes from the ini-file" . "\n";
  print "-o, --output-file := file to send output to instead to send it to a TELEGRAM Channel" . "\n";
  print "  -v [0-6], --verbose [0-6] := verbose logging, STANDARD Loglevel is set to 4" . "\n";
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
      $av_obj_LOGGER->trace("debug \$av_tmp_LINE: $av_tmp_LINE\n");
      
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
  
  $av_obj_INIFILE = Config::IniFiles->new( -file => "$av_loc_INIFILE" )
      or die "Block: $av_loc_BLOCK; Can't open < $av_loc_INIFILE: $!";

  @av_arr_STRING=();
  @av_arr_STRING = $av_obj_INIFILE->Parameters('LOGFILES'); # here you get an array of all keys of group LOGFILES, only the KEYs, not the VALUEs

  @av_arr_LOGFILES=();
  foreach  my $elem1 (@av_arr_STRING) # now all Values of the identified Keys will get read
  {
    push (@av_arr_LOGFILES, $av_obj_INIFILE->val('LOGFILES', $elem1)); # store values in array
    
    $av_obj_LOGGER->info("Block: $av_loc_BLOCK; " . $av_obj_INIFILE->val('LOGFILES', $elem1)); # debug
  }

  if ($av_std_TEST)
  {
    @av_arr_LOGFILES=('/var/log/syslog', '/var/log/auth.log'); # in case of TEST focus on these logfiles only
  }
  # fill array with tail-objects
  foreach ( @av_arr_LOGFILES ) {
      push( @av_arr_TAIL, File::Tail->new(name=>"$_",debug=>0,ignore_nonexistant=>1,reset_tail=>0) );
  }
  $av_tmp_DIR = $av_obj_INIFILE->val('PARAMS', 'tmp', '/tmp'); # Directory
  $av_loc_tgram_CHATID = $av_obj_INIFILE->val('PARAMS', 'chatid'); # TELEGRAM Channel-ID
  if ( ! defined $av_fn_REGEX ) # there might be some regex conf-file given by commandline options. If so, this has preference.
  {
    $av_fn_REGEX = $av_obj_INIFILE->val('PARAMS', 'regex', 'av_logfile_regex.conf'); # Regex File
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
"b|bot=s"   => sub { $av_loc_TELEGRAM = 1; $av_loc_tgram_BOT = $_[1] },        # Telegram BOT Token
"c|config=s"   => sub { $av_loc_CONFIG = 1; $av_loc_INIFILE=$_[1]; },          # ini-file
"f|logfiles=s"   => \@av_arr_LOGFILES,                                         # Logfiles to process
"h|help"   => \&av_help,                                                       # help
"l|logging"   => \$av_std_LOGGING,                                             # logging
"chatid=s"   => \$av_loc_tgram_CHATID,                                         # Telegram Channel
"logfile=s"  => sub { $av_std_LOGGING = 1; $av_std_LOGFILE=$_[1] },            # logfile to use
"o|output-file=s"  => sub { $av_loc_OUTPUT = 1; $av_loc_OUTFILE=$_[1] },       # Output to file instead of TELEGRAM
"t|test"   => \$av_std_TEST,                                                   # test
"v|verbose:4"  => \$av_std_VERBOSE,                                            # verbose + loglevel
"r|regex=s"  => \$av_fn_REGEX,                                                 # logfile to use
);

#
# processing GetOptions Parameters
#
if ( $av_std_LOGGING && ! defined $av_std_LOGFILE )
{
  print "no logfile path given" . "\n";
  exit(1);
}

#
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

###
### chech if TEST - and change some values of variables
###
if ( $av_std_TEST ) # only if not test set the PID into the PID-File
{
  $av_loc_INIFILE="$av_tmp_DIR/av_logfile.ini";
}
else
{
  open($av_fh_FILE, ">./av_logfile.pid");
  print $av_fh_FILE $$;
  close($av_fh_FILE);
}

###
### check on output-file
###
if ( defined $av_loc_OUTFILE )
{
  # create output-file specified
  $av_obj_OUTFILE = File::Touch->new()->touch("$av_loc_OUTFILE"); # create the output-file specified on commandline options

  # Datei einlesen
  open($av_fh_OUTFILE, ">>:encoding(UTF-8)", "$av_loc_OUTFILE") 
    or die "Couldn't open file $av_loc_OUTFILE, $!";
  $av_fh_OUTFILE->autoflush;
}

###
### ini-File einlesen
###
av_inifile_read();
if ( defined $av_fn_REGEX )
{
  $av_loc_REGEXFILE=$av_fn_REGEX;
}

if ( $av_std_TEST ) # if TEST, get the regex-file from some temporary directory
{
  $av_loc_REGEXFILE="$av_tmp_DIR/av_logfile_regex.conf";
}

###
### regex-conf einlesen
###

%av_ha_MATRIX=();
@av_arr_INCLUDES=();
push(@av_arr_INCLUDES,$av_loc_REGEXFILE);
av_regexfile_read($av_loc_REGEXFILE);

#$av_obj_REGEXFILE = File::Modified->new(files=>[$av_loc_REGEXFILE]); # create the object to check if the regexfile gets modified
#$av_tmp_STRING = join(",",@av_arr_INCLUDES);
$av_obj_REGEXFILE = File::Modified->new(files=>\@av_arr_INCLUDES); # create the object to check if the regexfile gets modified

$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_BASENAME: $av_std_BASENAME\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_DIRNAME: $av_std_DIRNAME\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_LOGGING: $av_std_LOGGING\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_LOGFILE: $av_std_LOGFILE\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_loc_TELEGRAM: $av_loc_TELEGRAM\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_TEST: $av_std_TEST\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_std_VERBOSE: $av_std_VERBOSE\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_loc_REGEXFILE: $av_loc_REGEXFILE\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \@av_arr_LOGFILES: @av_arr_LOGFILES\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_loc_OUTPUT: $av_loc_OUTPUT\n"); # debug
$av_obj_LOGGER->debug("Block: $av_loc_BLOCK - \$av_loc_OUTFILE: $av_loc_OUTFILE\n"); # debug

###
### prepare Telegram Object
###

if ( $av_loc_TELEGRAM && defined $av_loc_tgram_BOT )
{
  $av_obj_TGRAM = WWW::Telegram::BotAPI->new(
   token => "$av_loc_tgram_BOT"
  );
}
else {
  $av_obj_LOGGER->error("Block: $av_loc_BLOCK - TELEGRAM Bot cannot get initialized"); # debug
  exit(1);
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
if ( $av_loc_TELEGRAM )
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
  else {
    unless ( eval
    {
      $av_obj_TGRAM->sendMessage (
        {
            chat_id => $av_loc_tgram_CHATID,
            text    => hostname() . " " . basename($0) . " " . "restarted",
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
    push(@av_arr_INCLUDES,$av_loc_REGEXFILE);
    av_regexfile_read($av_loc_REGEXFILE);
    $av_obj_REGEXFILE->update();
    
    $av_obj_LOGGER->info("Block: $av_loc_BLOCK - $av_loc_REGEXFILE changed; read again!"); # debug

    # message only to telegram - not to output-file
    if ( $av_loc_TELEGRAM )
    {
      unless ( eval
      {
        $av_obj_TGRAM->sendMessage (
          {
              chat_id => $av_loc_tgram_CHATID,
              text    => hostname() . " " . "$av_loc_REGEXFILE changed; read again!",
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
  else {
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
        if ( substr($line, 0, 1) eq "." )
        {
          $av_tmp_PATTERN = $line;
          if ( $av_tmp_LINE =~ /$av_tmp_PATTERN/ )
          {
            $av_tmp_DELETED=1;
            $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - line deleted from " . $av_obj_TMP->{input} . "!");
            last;
          }
        }
        if ( substr($line, 0, 1) eq "-" )
        {
          $av_tmp_PATTERN = substr($line,1);
          if ( $av_tmp_LINE =~ /$av_tmp_PATTERN/ )
          {
            $av_tmp_DELETED=1;
            $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - line deleted from " . $av_obj_TMP->{input} . "!");
            last;
          }
        }
        if ( substr($line, 0, 1) eq "+" )
        {
          $av_tmp_PATTERN = substr($line,1);
          if ( $av_tmp_LINE =~ /$av_tmp_PATTERN/ )
          {
            $av_tmp_DELETED=0;
            $av_obj_LOGGER->trace("Block: $av_loc_BLOCK - line deleted from " . $av_obj_TMP->{input} . "!");
            last;
          }
        }
      }
      if ( ! $av_tmp_DELETED && length($av_tmp_LINE) > 1 )
      {
        $av_tmp_CURRLINE = $av_tmp_LINE;
        $av_tmp_CURRLINE =~ s/(^\S{3} \d{1,2} \d{2}:\d{2}:\d{2} |\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3} \- \- \[.*\d{4}\] )?//;
        if ( $av_tmp_CURRLINE eq $av_tmp_OLDLINE )
        {
          $av_tmp_DELETED=1;
          $av_obj_LOGGER->info("Block: $av_loc_BLOCK - double line: $av_tmp_OLDLINE");
        }
        else
        {
          $av_tmp_OLDLINE = $av_tmp_LINE;
          $av_tmp_OLDLINE =~ s/(^\S{3} \d{1,2} \d{2}:\d{2}:\d{2} |\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3} \- \- \[.*\d{4}\] )?//;
          $av_obj_LOGGER->debug("Block: $av_loc_BLOCK - backup pure line: $av_tmp_OLDLINE");
        }
      }
      if (!$av_tmp_DELETED && length($av_tmp_LINE) > 1 )
      {
        $av_loc_BLOCK="TELEGRAM";
        $av_obj_LOGGER->debug("Block: $av_loc_BLOCK - will get sent: $av_tmp_LINE");
        $av_tmp_LINE =~ s/<|>//g;
        $av_tmp_STRING = hostname() . " " . "Logfile: " . "<strong>" . $av_obj_TMP->{input} . "</strong>" . " " . $av_tmp_LINE;

        # write line to TELEGRAM Channel - if
        if ( $av_loc_TELEGRAM )
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
        if ( $av_loc_OUTPUT )
        {
          $av_tmp_STRING = $av_obj_DT->ymd . " " . $av_obj_DT->hms . " " . hostname() . " " . "Logfile: " . $av_obj_TMP->{input} . " " . $av_tmp_LINE;
          print $av_fh_OUTFILE $av_tmp_STRING;
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
