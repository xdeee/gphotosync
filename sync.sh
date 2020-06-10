#!/bin/bash

GPLOCK=~/gphotosync/run.lock

if [[ `lsof -c ruby | grep $GPLOCK` ]]
then
	echo "GP Sync is still running. Try later"
	exit
fi

rsync -avh --ignore-existing --progress ~/storage/GooglePhoto/ ~/storage/CameraUpload
