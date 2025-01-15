#!/bin/bash

set -o xtrace

# =====
# Author: Karl-Heinz Fischbach
# Date: 30.10.2011
# Content: welche rechner sind am netz
# 
# Copyright (C) 2012  Karl-Heinz Fischbach
# This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License along with this program; if not, see <http://www.gnu.org/licenses/>.
# 
# Changelog: 
# 
# =====

#  _      __        _       _     _      
#   \    / /       (_)     | |   | |     
#  \ \  / /_ _ _ __ _  __ _| |__ | | ___ 
#   \ \/ / _` | '__| |/ _` | '_ \| |/ _ \
#    \  / (_| | |  | | (_| | |_) | |  __/
#     \/ \__,_|_|  |_|\__,_|_.__/|_|\___|
#                                        
#                                        
### variables block

export TZ=CET

#  ______                _   _                 
#    ____|              | | (_)                
#   |__ _   _ _ __   ___| |_ _  ___  _ __  ___ 
#    __| | | | '_ \ / __| __| |/ _ \| '_ \/ __|
#   |  | |_| | | | | (__| |_| | (_) | | | \__ \
#  _|   \__,_|_| |_|\___|\__|_|\___/|_| |_|___/
#                                              
#                                              
### functions commands block

av_help()
{
echo -e "standard usage:"
echo -e "av_standard.sh [-h, --help] [-l, --logging] [-t, --test] [-v, --verbose] [-d, --debug] [--Version]"
echo -e "options are:"
echo -e "  -d, --debug := debugging mode"
echo -e "  -f, --force := force running"
echo -e "  -h, --help := this message - exit"
echo -e "  -l, --logging := log stdout and stderr to file"
echo -e "\tfile is stored in /var/userlog and will have job_ as prefix and .log as suffix"
echo -e "  -v, --verbose := verbose logging"
echo -e "  --Version, := show Version of script - exit"

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

###
### schleife um alle positional parameters abzupruefen
###

av_std_POSPAR=$(getopt -o "h" -l "help" -- "$@")

#
# Standard:
# -d, --debug
# -h, --help
# -l, --logging
# -t, --test
# -v, --verbose
# --version
#
[[ "$?" -ne 0 ]] && av_std_EXIT=1

eval set -- "${av_std_POSPAR}"

[[ "$?" -ne 0 ]] && av_std_EXIT=1

echo "\$\@ = $@"
echo "\$\* = $*"
echo "\$\# = $#"

echo "\$av_std_POSPAR = ${av_std_POSPAR}"

while [ ! -z "$1" ]
do
  case "$1" in
    -h | --help) 
			av_help
			exit 0
			;;
    --)
    	shift
    	break
    	;;
    *)
    	echo "unidentified Argument=$1"
    	break
    	;;
  esac

  shift
done

###
### wenn was in der parameterprüfung falsch gelaufen ist dann exit
###
[[ "${av_std_EXIT}" -eq "1" ]] && exit 1


#  __  __       _         _____                  
#    \/  |     (_)       |  __ \                 
#   \  / | __ _ _ _ __   | |__) | __ ___   ___   
#   |\/| |/ _` | | '_ \  |  ___/ '__/ _ \ / __|  
#   |  | | (_| | | | | | | |   | | | (_) | (__ _ 
#  _|  |_|\__,_|_|_| |_| |_|   |_|  \___/ \___(_)
#                                                
#                                                
### main procedure

echo $$>./av_logfile_wrapper.pid

while [ 1 ]; do
  /usr/bin/perl ./logfile.pl -l -v 4 --bot '<BOT Key>'
  wait
  sleep 60
done

#  ______           _   _____                  
# |  ____|         | | |  __ \                 
# | |__   _ __   __| | | |__) | __ ___   ___   
# |  __| | '_ \ / _` | |  ___/ '__/ _ \ / __|  
# | |____| | | | (_| | | |   | | | (_) | (__ _ 
# |______|_| |_|\__,_| |_|   |_|  \___/ \___(_)
#                                              
#                                              
### end procedure

