# EasyContainer
EasyContainer (ec) is a Command-line tool and also a Webpanel for easy Management of WordPress Sites running under NGINX, PHP, MySQL, redis-server, memcached inside a Linux Container.

**EasyContainer is made for Ubuntu 16.04 LTS**


 - LXD/LXC from Ubuntu 16.04 LTS
 - ZFS from Oracle
 - easyengine from RTCamp
 
  
##Install it easy with:
```bash
 wget https://github.com/ingobaab/easycontainer/ec -O ec && sudo ec
```

##Copyright:
GPL


| Name  | Port Number | Inbound | Outbound  |
|:-----:|:-----------:|:-------:|:---------:|
|SSH    |22           | ✓       |✓          |
|HTTP    |80           | ✓       |✓          |
|HTTPS/SSL    |443           | ✓       |✓          |
|EE Admin    |22222           | ✓       |          |
|GPG Key Server    |11371           |        |✓          |
