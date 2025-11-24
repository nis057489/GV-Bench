# For downloading from Sharepoint Via CLI:

Follow the instructions here: <https://gist.github.com/cdeitrick/b5ce1dc9b78516694942b79e440023ff>

You will get something like this (note: you have to copy this from your own Chrome session because the token is short lived):

```sh
curl 'https://southeastasia1-mediap.svc.ms/transform/zip?cs=fFNQTw' \
  -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' \
  -H 'accept-language: en-GB,en-US;q=0.9,en;q=0.8' \
  -H 'cache-control: max-age=0' \
  -H 'content-type: application/x-www-form-urlencoded' \
  -H 'origin: https://hkustconnect-my.sharepoint.com' \
  -H 'priority: u=0, i' \
  -H 'sec-ch-ua: "Chromium";v="142", "Google Chrome";v="142", "Not_A Brand";v="99"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'sec-fetch-dest: iframe' \
  -H 'sec-fetch-mode: navigate' \
  -H 'sec-fetch-site: cross-site' \
  -H 'sec-fetch-storage-access: active' \
  -H 'upgrade-insecure-requests: 1' \
  -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36' \
  --data-raw 'zipFileName=images.zip&guid=7b95dd0f-15e0-41cb-9288-df155c791d35&provider=spo&files=%7B%22items%22%3A%5B%7B%22name%22%3A%22images%22%2C%22size%22%3A0%2C%22docId%22%3A%22https%3A%2F%2Fhkustconnect-my.sharepoint.com%3A443%2F_api%2Fv2.0%2Fdrives%2Fb%21uy5SynhgDE2YtKgQ87m1yV1zveAZ1Z5OsEOy1Q0zTncQDgQhRtTLSJyFOB8YBkGm%2Fitems%2F016IVHXZN6QIM3W6XSQ5B3WNWM4S4MD4IR%3Fversion%3DPublished%26access_token%3Dv1.eyJzaXRlaWQiOiJjYTUyMmViYi02MDc4LTRkMGMtOThiNC1hODEwZjNiOWI1YzkiLCJhdWQiOiIwMDAwMDAwMy0wMDAwLTBmZjEtY2UwMC0wMDAwMDAwMDAwMDAvaGt1c3Rjb25uZWN0LW15LnNoYXJlcG9pbnQuY29tQDZjMWQ0MTUyLTM5ZDAtNDRjYS04OGQ5LWI4ZDZkZGNhMDcwOCIsImV4cCI6IjE3NjQwMDcyMDAifQ.CiMKCXNoYXJpbmdpZBIWQXU5OWJDZFlkRWVTd0dDemNkK2FkQQoICgNzdHASAXQKCgoEc25pZBICMzMSBgiY6DsQARoOMTI0LjE3MC4xNi4yMDMiFG1pY3Jvc29mdC5zaGFyZXBvaW50KixLVG9ZNlJvVzlxTWJYN3VLcTNlOW41QllVdlFQWmlIVkh4OFRVMVRuL0RrPTB6OAFKEGhhc2hlZHByb29mdG9rZW5iBHRydWVySzBoLmZ8bWVtYmVyc2hpcHx1cm4lM2FzcG8lM2F0ZW5hbnRhbm9uIzIzYmFhZmI0LTQ5ZWQtNDNhMi05ZjUyLWE4YTMxN2E4NWQ4ZHoBMMIBSzAjLmZ8bWVtYmVyc2hpcHx1cm4lM2FzcG8lM2F0ZW5hbnRhbm9uIzIzYmFhZmI0LTQ5ZWQtNDNhMi05ZjUyLWE4YTMxN2E4NWQ4ZA.dJnd-AnqNPxhRwePX5Sm_uK4Lr4bnMUkC5gvP-QSdVo%22%2C%22isFolder%22%3Atrue%7D%5D%7D&oAuthToken=' --output images.zip
```

Notice I appended `--output images.zip`, do the same.