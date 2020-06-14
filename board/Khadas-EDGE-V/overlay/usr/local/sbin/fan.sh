#!/bin/sh
# fan.sh - automatic control of PWM fan on RK3399

trap quit_fan SIGINT SIGSTOP SIGTERM SIGQUIT

quit_fan() {
    pkill -P $$ sleep
    exit
}

MINTEMP=50
MAXTEMP=65

SYSCTL="/sbin/sysctl"
CUT="/usr/bin/cut"
PWM="/usr/sbin/pwm"

# NanoPC-T4
PWM_DEVICE="/dev/pwm/pwmc1.0"

# Khadas-EDGE
PWM_DEVICE="/dev/pwm/pwmc0.0"

while [ TRUE ]; do
    TEMP=`${SYSCTL} -n hw.temperature.CPU | ${CUT} -d . -f 1`
    DISABLE=0
    if [ "$TEMP" -gt ${MAXTEMP} ]; then
        # set speed to maximum
        PERCENTAGE=0
    elif [ "$TEMP" -le ${MINTEMP} ]; then
        # set speed to minimum
        PERCENTAGE=100
        DISABLE=1
    else
        PERCENTAGE=$((TEMP - MINTEMP))
        PERCENTAGE=$(((PERCENTAGE * 100) / 15))
        echo "Temperature is ${TEMP}, which is percentage ${PERCENTAGE}."
        PERCENTAGE=$((100 - PERCENTAGE))
    fi

    if [ $DISABLE -eq "1" ]; then
       ${PWM} -f ${PWM_DEVICE} -D
    else
        if [ "${PERCENTAGE}" -eq 0 ]; then
            ${PWM} -f ${PWM_DEVICE} -E -d 0 -p 0
        else
            ${PWM} -f ${PWM_DEVICE} -E -d ${PERCENTAGE}% -p 30000
        fi
    fi

    sleep 60 &
    wait $!
done

