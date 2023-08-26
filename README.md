# logfile_telegram
Logfile analyzer to send result to telegram channel

Perl script
You can monitor one or more linux logfiles, similar as the system command "tail".

You can filter the logfile entries by some regex espressions, stored in a configuration file by logfile.
All logfile entries passing the regex check will get sent to a telegram channel, configured in a ini-file.
The TELEGRAM Bot token has to be handed over to the script via the command-line option --bot.

