#!/bin/bash

CONFIGS=()
CONFIGS+=("16x16c-cmesh" "16x16c-mcm")
CONFIGS+=("256c-mono")
CONFIGS+=("4x16c-cmesh" "4x16c-mcm")
CONFIGS+=("64c-mono")
CONFIGS+=("1c-mono")

maximum_children=8
num_trials=5
force=0

DELAYS=()

# USAGE <value> <array...>
# returns 0 if match
# ex. arrayContains "hello" "${myArray[@]}"
function arrayContains() {
	local value="$1"
	shift
	array=("$@")
	for a in "${array[@]}"; do
		if [[ "$a" == "$value" ]]; then
			return 0
		fi
	done
	return 1
}

function add_delay_range {
	local delay_start=$1
	local delay_end=$2
	local delay_incr=1
	if [[ $# -ge 3 ]]; then delay_incr=$3; fi
	for (( delay=$delay_start ; delay <= $delay_end ; delay+=$delay_incr )); do
		arrayContains $delay "${DELAYS[@]}"
		if [[ $? -ne 0 ]]; then  # if does not contain
			DELAYS+=($delay)
		fi
	done
}

delay_set="test"
#delay_set="full"

if [[ "$delay_set" == "test" ]]; then
	DELAYS+=(1 2 3 5 8 10 14 18 25 30 40 50 60 70 90 125 175 300 500 1000 2000)
	num_trials=3
	CONFIGS=("16x16c-ooo_mcm" "16x16c-ooo_cmesh" "256c-ooo_mono" "1c-ooo_mono")
	#CONFIGS=("16x16c-mcm" "16x16c-cmesh" "256c-mono" "1c-mono")
else
	add_delay_range 1 10
	add_delay_range 12 22 2
	add_delay_range 25 40 5
	add_delay_range 50 100 10
	add_delay_range 125 250 25
	add_delay_range 300 500 50
	add_delay_range 600 1000 100
	add_delay_range 1250 2000 250
	for d in "${DELAYS[@]}"; do
		echo $d
	done
	exit 1
fi



old_pwd="$(pwd)"

function usage {
	echo -e "USAGE [-f][-c <children>] [directory]"
	echo -e "Run ubench"
	echo -e "-c CHLIDREN\tMax number of child tasks."
	echo -e "-f \t\tForce to rerun all ubench tests."
	# echo -e "-w WORK\t\tSet amount of work."
	echo -e "directory \tWhere to store results. Default: relative to /scratchpad/ubench"

	echo -e "-h \t\tPrint this help."
	exit 1
}

positional_args=()
cmdLineBackup="$@"
while [[ $# -ne 0 ]]; do
	arg="$1"
	consumed_args=1

	if [[ "${arg:0:1}" == "-" ]]; then
		for (( i=1; i<${#arg}; i++ )); do
			opt="${arg:$i:1}"
			case "$opt" in
				c)
					# Since this requires a param, either
					# - be the last char. The next arg is its param.
					# - the rest of this arg is its param.
					j=$(expr $i + 1 )
					if [[ $j -eq ${#arg} ]]; then 
						maximum_children="$2"
						consumed_args=2
					else
						maximum_children="${arg:$j}"
					fi
					break
					;;
				f)
					force=2
					;;
				h)
					usage
					;;
				*)
					echo "Unknown option -$opt"
					usage
					;;
			esac
		done
	else
		positional_args+=($arg)
	fi

	 if [[ $consumed_args -gt $# ]]; then
		 echo "Option was not provided enough arguments ($1)"
		 usage
	 fi
	 shift $condumed_args
done

# set $@ to be the positional args
set -- "${positional_args[@]}"

base_dir="/scratchpad/ubench"
if [[ $# -ge 1 ]]; then
	dir="$1"
	if [[ "${dir:0:1}" == "/" || "${dir:0:1}" == "~" ]]; then
		base_dir="$dir"
	else
		base_dir="$base_dir/$dir"
	fi
fi

if [[ ! -d $base_dir ]]; then
	mkdir -p $base_dir
fi
cd $base_dir


function wait_if_too_many_children() {
	max_children=$1
	num_children=$(pgrep -c -P$$)
	wait_delay=1
	while [[ $num_children -ge $max_children ]]; do
		# echo "sleeping for $wait_delay s"
		sleep $wait_delay
		if [[ $wait_delay -le 60 ]]; then
			wait_delay=$(expr 2 \* $wait_delay)
		fi
		num_children=$(pgrep -c -P$$)
	done
}

if [[ -f run.log ]]; then
	mv run.log run-bkup.log -f
fi

function run_test {
	local config="$1"
	local trial="$2"
	local delay="$3"
	
	local out_dir="$base_dir/$trial/ub_1k_$delay-$config"
	local log_file="/dev/null"

	if [[ ! -d $out_dir ]]; then
		mkdir -p $out_dir
	fi

	cmd="run_test.sh invx $out_dir -i 1000-$delay -c $config &> $log_file"
	local skip_test=0
	check_done="$(checkDone.sh $base_dir/$trial -g "ub_1k_$delay-$config")"
	if [[ ($force -lt 2) && ("$check_done" == "All 1 tests completed successfully") ]]; then
		skip_test=1
	fi
	#echo "$delay ($skip_test): $check_done"
	if [[ $skip_test -eq 1 ]]; then
		echo "Skip: $cmd" >> run.log
	else
		echo "Start ($(date)): $cmd" >> run.log
		eval "$cmd" &
	fi
}

ticker=1
function reset_tick {
	ticker=1
}
function echo_tick {
	if [[ $# -ge 1 ]]; then  # reset ticker and print
		reset_tick
	fi
	if [[ $((ticker % 20)) == 0 ]]; then
		echo -n "O"
	elif [[ $((ticker % 5)) == 0 ]]; then
		echo -n "o"
	else
		echo -n "."
	fi
	((ticker+=1))
}

# sort delays from largest to smallest
DELAYS=($(echo ${DELAYS[@]} | tr ' ' '\n' | sort -nr))


#config="1c-mono"
#trial=1
#echo "Start config: $config"
#for delay in "${DELAYS[@]}"; do
#	wait_if_too_many_children $maximum_children
#	echo_tick
#	run_test $config $trial $delay
#done
#for (( trial=2 ; trial <= $num_trials ; trial++ )); do
#	if [[ ! -d $base_dir/$trial ]]; then
#		mkdir $base_dir/$trial
#	fi
#	for delay in "${DELAYS[@]}"; do
#		fname="ub_1k_$delay-$config"
#		ln -s $base_dir/1/$fname $trial/$fname
#	done
#done
#echo ""

for (( trial=1 ; trial <= $num_trials ; trial++ )); do
	echo "Start trial: $trial"
	if [[ ! -d $base_dir/$trial ]]; then
		mkdir $base_dir/$trial
	fi
	for config in ${CONFIGS[@]}; do
		reset_tick
		echo "Start config: $config"
		for delay in "${DELAYS[@]}"; do
			wait_if_too_many_children $maximum_children
			echo_tick
			run_test $config $trial $delay
		done
		echo ""
	done
done

wait
echo "Done"

cd $old_pwd
