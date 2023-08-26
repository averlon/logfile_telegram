# logfile_to_telegram
Logfile analyzer to send result to telegram channel

Perl script
You can monitor one or more linux logfiles, similar as the system command "tail".

You can filter the logfile entries by some regex expressions, stored in a configuration file by logfile. Either stored in the main regex-conf or inserted via "include"-statements from the main regex-conf file.
All logfile entries passing the regex check will get sent to a telegram channel, configured in a ini-file.
The TELEGRAM Bot token has to be handed over to the script via the command-line option --bot.

## example ini-file

## example regex-conf file

## how to call the script
