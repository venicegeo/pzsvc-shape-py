#!/bin/bash

# Copyright 2017, RadiantBlue Technologies, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ---Setup---
PZKEY=$PZ_API_KEY
curl="curl -S -s -u $PZKEY:"" -H Content-Type:application/json"
uuidRegex='(?:[a-g]|[0-9]){8}-(?:(?:[a-g]|[0-9]){4}-){3}(?:[a-g]|[0-9]){12}'

# ---Wait until new build of bfalg-shape is ready---
responseCode=404
failCount=0
while [[ $responseCode != 200 ]]; do
    echo "Waiting for pzsvc-shape.int.geointservices.io ..."
    responseCode=`curl -s -o /dev/null -w '%{http_code}' https://pzsvc-shape.int.geointservices.io`
    if [[ $responseCode != 200 ]]; then
      failCount=$((failCount+1))
      echo Fail number $failCount
      if [[ $failCount -eq 10 ]]; then
        echo Failed to start
        exit 1
      fi
      sleep 10s
    fi
done


# ---Getting serviceId---
serviceCurl=`$curl -X GET https://piazza.int.geointservices.io/service?keyword=BF_Algo_SHAPE_PY`
serviceId=`echo $serviceCurl|grep -Po $uuidRegex`

# ---Create test job using bfalg-shape service---
jobPayload='{
        "data": {
            "dataInputs": {
                "body": {
                    "content": "{\"cmd\":\"-f landsatImage.TIF -o shape.geojson\",\"inExtFiles\":[\"https://landsat-pds.s3.amazonaws.com/L8/139/045/LC81390452014295LGN00/LC81390452014295LGN00_B1.TIF\"],\"inExtNames\":[\"landsatImage.TIF\"],\"outGeoJson\":[\"shape.geojson\"]}",
                    "type": "body",
                    "mimeType": "application/json"
                }
            },
            "dataOutput": [{"mimeType": "application/json","type": "text"}],
            "serviceId": "'
jobPayload=$jobPayload$serviceId'"
        },
        "type": "execute-service"
    }'
echo "Creating job"
jobCurl=`$curl -X POST https://piazza.int.geointservices.io/job -d "$jobPayload"`
jobId=`echo $jobCurl|grep -Po $uuidRegex`


# ---Checking if job started---
if [ "$jobId" = "" ]; then
  echo "Could not create job"
  exit 1
fi
echo Created job with jobId $jobId


# ---Checking job status until success or otherwise---
statusRegex='"status"\s*:\s*"([^"]*)'
jobStatus="foo"
while [[ $jobStatus != "Success" ]]; do
  jobStatus=`$curl -X GET https://piazza.int.geointservices.io/job/$jobId`
  if [[ "$jobStatus" =~ $statusRegex ]]; then
    jobStatus="${BASH_REMATCH[1]}"
  fi
  if [ "$jobStatus" = "" ]; then
    echo Bad curl
    exit 1
  fi
  echo Current status: $jobStatus
  if [ "$jobStatus" = "Cancelled" ]; then
    echo "Job $jobId ended with status Cancelled"
    exit 1
  fi
  if [ "$jobStatus" = "Error" ]; then
    echo "Job $jobId ended with status Error"
    exit 1
  fi
  if [ "$jobStatus" = "Fail" ]; then
    echo "Job $jobId ended with status Fail"
    exit 1
  fi
  sleep 10s
done


# ---Getting dataId from completed job---
echo "Job $jobId finished. Getting dataId"
dataIdRegex='"dataId"\s*:\s*"([^"]*)'
jobStatus=`$curl -X GET https://piazza.int.geointservices.io/job/$jobId`
dataId=""
if [[ "$jobStatus" =~ $dataIdRegex ]]; then
  dataId="${BASH_REMATCH[1]}"
fi


# ---Checking if dataId received---
if [ "$dataId" = "" ]; then
    echo "Error getting dataId. Exiting test."
    exit 1
fi
echo "Retrieved dataId $dataId"


# ---Getting fileId from dataId---
echo "Getting fileId using dataId $dataId"
fileCurl=`$curl -X GET https://piazza.int.geointservices.io/file/$dataId`
fileIdRegex='"shape.geojson"\s*:\s*"([^"]*)'
fileId=""
if [[ "$fileCurl" =~ $fileIdRegex ]]; then
  fileId="${BASH_REMATCH[1]}"
fi
if [ "$fileId" = "" ]; then
    echo "Error getting fileId. Exiting test."
    exit 1
fi
echo "Retrieved fileId $fileId"


# ---Getting geojson data from file---
echo "Getting geojson data at fileId $fileId"
geojsonData=`$curl -X GET https://piazza.int.geointservices.io/file/$fileId`
errorRegex='"type"\s*:\s*"error"'
errorCheck=`echo $geojsonData|grep -Po $errorRegex`
if [ "$errorCheck" != "" ]; then
  echo "Error getting geojson data. Exiting test."
  exit 1
fi
echo $geojsonData
exit 0
