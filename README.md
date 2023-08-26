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

At any position, you can set an "include <filename>.conf"-statement. This enables you to keep the regex definitions valid for a specific logfile in a separate file, since the conf-file can become a big file with lots of lines.
Although not recommended, you even can set the include-statment inside some included conf-file. So the include-statement is working recursively.


## how to call the script
