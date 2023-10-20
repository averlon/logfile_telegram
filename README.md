# logfile_to_telegram
Logfile analyzer to send result to telegram channel

Perl script
You can monitor one or more linux logfiles, similar as the system command "tail".

You can filter the logfile entries by some regex expressions, stored in a configuration file by logfile. Either stored in the main regex-conf or inserted via "include"-statements from the main regex-conf file.
All logfile entries passing the regex check will get sent to a telegram channel, configured in a ini-file.
The TELEGRAM Bot token has to be handed over to the script via the command-line option --bot.

## example ini-file

filename: "av_logfile.ini"

The configuration file filename can be handed over to the script via the commandline option --config <filename including path>

```
[LOGFILES]
FILE1=/var/log/f42240ro.log
FILE2=/var/log/syslog
FILE3=/var/log/mail.log
FILE4=/var/log/named/named.log
FILE5=/var/log/auth.log

[PARAMS]
tmp=/tmp
regex=logfile_regex.conf
chatid=-00000
```

## example regex-conf file
filename: from ini-file
```
#####
# This file is used to filter logfile messages to be sent to the TELEGRAM Channel
# Format:
# - all lines are regex expressions to be compared with the logfile line
# - the first character (+ or -) defines, if the line not be sent to the TELEGRAM Channel (-) or must be sent (+)
# - alle lines of the logfile which do not match with one of the regex expressions are sent to the TELEGRAM Channel anyway
# - it could be a good idea to place all (+)-lines first in the block of a logfile
#
# The file is split into sections. Each section, represented by [<filename of a logfile>], contain the regex expressions relevant for this logfile.
# So you can and have to define regex expressions per logfile.
# There is (currently) no "DEFAULT" set of regex expressions valid for alle logfiles!
# As you might imagine, lines starting with a "#" are treated as comments!
#####
[/var/log/syslog]
##################################################
# Syslog; Logfile: /var/log/syslog
##################################################

+Startup finished

-kernel.*

-acpid\[\d{1,}\].*

-anacron\[\d{1,}\]: Will run job `cron\.daily' in 5 min
-anacron\[\d{1,}\]: Job `cron\.daily' started
-anacron\[\d{1,}\]: Job `cron\.daily' terminated
-anacron\[\d{1,}\]: Job `cron\.weekly' started
-anacron\[\d{1,}\]: Job `cron\.weekly' terminated
-anacron\[\d{1,}\]: Jobs will be executed sequentially
-anacron\[\d{1,}\]: Updated timestamp for job `cron\.daily'.*
-anacron\[\d{1,}\]: Updated timestamp for job `cron\.weekly'.*
-anacron\[\d{1,}\]: Anacron .* started on.*
-anacron\[\d{1,}\]: Normal exit \(\d{1,} job run\)
-anacron\[\d{1,}\]: Normal exit \(\d{1,} jobs run\)
include logfile_mail.conf
```

At any position, you can set an ```include <filename>.conf```-statement. This enables you to keep the regex definitions valid for a specific logfile in a separate file, since the conf-file can become a big file with lots of lines.
Although not recommended, you even can set the include-statment inside some included conf-file. So the include-statement is working recursively.


## how to call the script
```
/usr/bin/perl logfile.pl -l -v 4 --logfile job_logfile.log --bot '<telegram bot token>' --output-file /var/log/av_logfile.log 2>>~/logfile.stderr 1>>~/logfile.stdout
```
To redirect the output is naturally on your own!

If you want to debug the script it might be handy to add the "-t" commandline option and increase the logging verbosity:
```
/usr/bin/perl -d logfile.pl -t -l -v 6 --logfile job_logfile.log --bot '<telegram bot token>' --output-file /var/log/av_logfile.log 2>>~/logfile.stderr 1>>~/logfile.stdout
```
The advantage of the "-t" option is, that most of the configuration files are fetched from the "tmp"-directory given in the ini-file.
Since the temporary directory is not valid before the ini-file was processed, the STANDARD for the temp-directory is "/tmp"! So the ini-file itself is searched there, if you don't use the commandline option "--config".

## Allowed commandline options:

```
-b <bot token>, --bot <bot token>
```
TELEGRAM Bot Token
If set, logfile messages will be sent to the TELEGRAM Chat/Channel

```
-h, --help
```
If this commandline options is given, only the Help Message will be printed. All other commandline options are ignored.

```
-f <comma separated list of logfiles>, --logfiles <comma separated list of logfiles>
```
comma separated list of logfiles to be processed.
Normally, the list of logfiles is defined in the ini-file, but can be overridden by this commandline option.

```
-l, --logging
```
If set, STDOUT and STDERR will be redirected to a file via "log4perl"

```
-t, --test
```
If set, Test-Mode is activated. This implies that some files are fetched from other directories.

```
-c <filepath>, --config <filepath>
```
You can specify a different ini-file to be processed.

```
-r <filepath>, --regex <filepath>
```
You can specify a different regex file to be processed.

```
--chatid <chatid>
```
ChatId of the TELEGRAM Chat where the messages shall be sent to!

```
-o <filepath>, --output-file <filepath>
```
If specified, the logfile messages will be written to defined file.

```
-v [0-6], --verbose [0-6]
```
Level of verbosity of the script.

## issue with TELEGRAM Bot number of messages
You might know, that you are only allowed to send a limited number of messages per timeframe via a TELEGRAM Bot.
Therefore, the script sometimes crashes with an error message from the TELEGRAM Bot that you have sent too many messages. The message at that time will get lost!

To restart the script automatically, I start the script via a "wrapper", a Shell-Script running in a loop!
```
#!/bin/bash

echo $$>./logfile_wrapper.pid

while [ 1 ]; do
  /usr/bin/perl ~/logfile.pl -l -v 4 --logfile ~/job_logfile.log --bot '<telegram bot token>' --output-file /var/log/av_logfile.log 2>>~/logfile.stderr 1>>~/logfile.stdout
  wait
  sleep 60
done
```
If you want to stop the script or reload the script once you probably have made you own changes you could do:
```
kill $(cat /home/<user>/logfile.pid)
```
to kill the script and reload it via the wrapper or
```
kill $(cat /home/<user>/logfile_wrapper.pid) - to kill the wrapper first and thereby prevent the wrapper to reastart the script once you kill it afterwards
kill $(cat /home/<user>/logfile.pid)
```

