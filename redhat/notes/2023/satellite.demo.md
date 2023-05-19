# satellite 作为yum repo的简单演示

客户购买了 redhat rhel 订阅，想在国内使用，但是 rhel 订阅在os上激活，是需要连接国外服务器的，由于众所周知的原因，国内访问有时候不稳定，甚至国外服务器本身有的时候就慢，那么这种情况下，客户就需要一个订阅的代理服务器。红帽的satellite产品，就是这样一个订阅注册代理服务器。

当然，satellite产品内涵很丰富，订阅注册代理只是一个其中一个很小的功能。satellite产品的标准使用场景是，用户有一个内网环境，里面有一个主机能联网，这个主机安装satellite，并向satellite导入订阅证书，启动yum repo镜像服务，iPXE, dhcp, dns服务等，这些服务在一起，就能让内网的其他主机具备了上电以后，自动安装rhel的能力，rhel装好以后，satellite还提供持续更新的功能。

所以satellite是一个带安装源的OS全生命周期管理维护产品，官方文档在这里：
- https://access.redhat.com/documentation/en-us/red_hat_satellite/6.13

本文，就演示一个最简单的场景，安装satellite，并且内网rhel在satellite上激活订阅，并使用satellite作为yum repo源。

实验架构图，请注意，本次实验展示的satellite的功能和场景很简单，其他satellite的功能，比如内容视图，satellite集群，离线操作等等很多功能，依然等待大家去探索。

![](./dia/satellite.demo.01.drawio.svg)

# 安装 satellite server

satellite的完整产品架构里面，有server，还有独立的capsule，我们是极简部署，而且server里面也有内置的capsule，所以我们这次就部署一个server就好了。

![](imgs/2023-05-17-22-58-51.png)

服务器用的是16C 32G，500G HDD的VM，实际项目里面，硬盘要大点。

另外，server要有域名，而且要配置好反向解析。

```bash
# satellite server
# 172.21.6.171
# dns resolve and reverse to panlab-satellite-server.infra.wzhlab.top

# satellite client host
# 172.21.6.172

# on satellite server
ssh root@172.21.6.171

# https://access.redhat.com/documentation/en-us/red_hat_satellite/6.13/html-single/installing_satellite_server_in_a_connected_network_environment/index

systemctl disable --now firewalld.service

hostnamectl set-hostname panlab-satellite-server.infra.wzhlab.top

ping -c1 localhost
# PING localhost(localhost (::1)) 56 data bytes
# 64 bytes from localhost (::1): icmp_seq=1 ttl=64 time=0.043 ms

ping -c1 `hostname -f`
# PING panlab-satellite-server.wzhlab.top (172.21.6.171) 56(84) bytes of data.
# 64 bytes from bogon (172.21.6.171): icmp_seq=1 ttl=64 time=0.047 ms

# active subscrition on this rhel.
subscription-manager register --auto-attach --username xxxxxxxxx --password xxxxxxxxxx

# add repo for satellite
subscription-manager repos --enable=rhel-8-for-x86_64-baseos-rpms \
  --enable=rhel-8-for-x86_64-appstream-rpms \
  --enable=satellite-6.13-for-rhel-8-x86_64-rpms \
  --enable=satellite-maintenance-6.13-for-rhel-8-x86_64-rpms
# Repository 'rhel-8-for-x86_64-baseos-rpms' is enabled for this system.
# Repository 'rhel-8-for-x86_64-appstream-rpms' is enabled for this system.
# Repository 'satellite-6.13-for-rhel-8-x86_64-rpms' is enabled for this system.
# Repository 'satellite-maintenance-6.13-for-rhel-8-x86_64-rpms' is enabled for this system.

dnf module enable satellite:el8

dnf update -y

dnf install satellite chrony sos -y

systemctl enable --now chronyd

# begin install satellite
satellite-installer --scenario satellite \
--foreman-initial-organization "My_Organization" \
--foreman-initial-location "My_Location" \
--foreman-initial-admin-username admin \
--foreman-initial-admin-password redhat
# ......
# 2023-05-16 22:41:17 [NOTICE] [configure] System configuration has finished.
#   Success!
#   * Satellite is running at https://panlab-satellite-server.infra.wzhlab.top
#       Initial credentials are admin / redhat

#   * To install an additional Capsule on separate machine continue by running:

#       capsule-certs-generate --foreman-proxy-fqdn "$CAPSULE" --certs-tar "/root/$CAPSULE-certs.tar"
#   * Capsule is running at https://panlab-satellite-server.infra.wzhlab.top:9090

#   The full log is at /var/log/foreman-installer/satellite.log
# Package versions are being locked.

```

安装很容易，但是时间有点长，十几分钟，官方建议套在 tmux 里面运行安装程序。安装完成了，浏览器直接访问 url 就可以了。

![](imgs/2023-05-16-22-50-40.png)

我们可以在系统里面，看到satellite server作为一个host已经存在了。

![](imgs/2023-05-16-23-07-37.png)

# 下载订阅信息

我们的业务场景，是内网主机都注册到satellite上来，这必然需要把红帽官网上的订阅信息导入到satellite里面去，我们来一步一步做一下。
<!-- export Subscription Manifest from redhat portal -->

首先，我们要去红帽官网，创建一个订阅分配，如果我们有100个订阅，都要用到satellite上，那么就分配100个来。我们做实验，就分配1个，后面好实验超用，还有添加数量的场景。

![](imgs/2023-05-16-23-51-22.png)

我们创建的订阅分配，类型和我们装的satellite版本要保持一致。

![](imgs/2023-05-16-23-52-08.png)

切换到订阅tab:

![](imgs/2023-05-16-23-53-01.png)

添加订阅，会打开一个页面，让你搜索你有的订阅，并挑选一个出来：

![](imgs/2023-05-16-23-59-18.png)

我们选好了订阅以后，设定数量，根据需要的数量来，一般情况，把你所以的订阅都加进来。我们做实验，就设置 1. 然后下载。

![](imgs/2023-05-17-00-09-53.png)

# 导入订阅信息

我们已经有了订阅信息文件，那么我们回到satellite管理界面里面，导入它。

![](imgs/2023-05-17-00-12-05.png)

完成以后，我们就能看到订阅信息了。

![](imgs/2023-05-17-00-18-28.png)

# 配置 yum repo 镜像

我们实验的目的，就是配置一个yum repo 镜像源出来，但是默认satellite使用的是on demand 的方式来下载 rpm，我们希望让他一气呵成，主动提前的下载好，那么需要做一个配置。

![](imgs/2023-05-17-11-18-07.png)

激活主动下载配置

![](imgs/2023-05-17-11-18-38.png)

做了主动下载配置以后，我们就来添加 yum 源。

![](imgs/2023-05-17-00-18-57.png)

我们先搜索 appstream 。

![](imgs/2023-05-17-00-21-12.png)

然后我们选择小版本

![](imgs/2023-05-17-00-21-45.png)

为了做实验，凸显效果，我们只选择8.6这个非最新版本。

![](imgs/2023-05-17-00-22-43.png)

我们再搜索 baseos ，并选择 8.6 版本

![](imgs/2023-05-17-00-23-02.png)

选择好了yum 源以后，我们开始手动同步。

![](imgs/2023-05-17-09-57-12.png)

选择要同步的repo, 开始

![](imgs/2023-05-17-09-57-43.png)

<!-- ![](imgs/2023-05-17-10-14-08.png) -->

经过漫长的时间，下载完成。

![](imgs/2023-05-17-14-33-41.png)

satellite服务器端的基本服务，就配置完了，我们看看系统情况。

```bash

satellite-maintain service list
# Running Service List
# ================================================================================
# List applicable services:
# dynflow-sidekiq@.service                   indirect
# foreman-proxy.service                      enabled
# foreman.service                            enabled
# httpd.service                              enabled
# postgresql.service                         enabled
# pulpcore-api.service                       enabled
# pulpcore-content.service                   enabled
# pulpcore-worker@.service                   indirect
# redis.service                              enabled
# tomcat.service                             enabled

# All services listed                                                   [OK]
# --------------------------------------------------------------------------------

df -h
# Filesystem      Size  Used Avail Use% Mounted on
# devtmpfs         16G     0   16G   0% /dev
# tmpfs            16G  148K   16G   1% /dev/shm
# tmpfs            16G  8.9M   16G   1% /run
# tmpfs            16G     0   16G   0% /sys/fs/cgroup
# /dev/sda3       499G  106G  393G  22% /
# /dev/sda2      1014M  265M  749M  27% /boot
# /dev/sda1       599M  9.6M  590M   2% /boot/efi
# tmpfs           3.2G     0  3.2G   0% /run/user/0

free -h
#               total        used        free      shared  buff/cache   available
# Mem:           31Gi        21Gi       1.7Gi       567Mi       7.9Gi       8.6Gi
# Swap:            0B          0B          0B

```

内存占用21G，硬盘占用 110G。这个数据给以后部署提供一个依据吧。。。

<!-- ![](imgs/2023-05-17-11-18-07.png)

![](imgs/2023-05-17-11-18-38.png) -->

我们查看capsule的使用资源情况。

![](imgs/2023-05-17-15-17-41.png)

# 配置 active key

我们导入了 subscription，要给rhel使用，需要创建active key并绑定。active key可以灵活的控制激活的 rhel 数量，确保我们不超量使用订阅。

![](imgs/2023-05-17-12-42-56.png)

随便起一个名字

![](imgs/2023-05-17-12-43-39.png)

active key的详细配置里面, 我们设置 host limite 为 unlimited, 这个建议设置为具体数字, 保证不超用。我们还要选择 environment， 简单的场景，默认的就好，这个配置能让我们把主机分成不同的group来管理。 content view 也是默认的， 这个配置可以让不同的主机组，看到的rpm 版本不同 。release version 放空，这个配置可以配置主机默认的release版本。

可以看到，satellite的功能很多，是面向大规模主机部署场景设计的。

![](imgs/2023-05-17-14-56-51.png)

然后，我们把订阅附加到 active key里面去。

![](imgs/2023-05-17-14-58-08.png)

我们的orgnization启用了 simple access control， 为了对比，我们先 disable它，后面我们会打开它，来做个对比。

![](imgs/2023-05-17-12-47-33.png)

取消 SAC 的激活

![](imgs/2023-05-17-12-48-05.png)

<!-- ![](imgs/2023-05-17-12-50-16.png) -->

# 注册主机

我们来创建就一个 URI, 目标rhel，curl这个 URL，会下载一个脚本，运行这个脚本，目标rhel就注册到我们的satellite server上了。

![](imgs/2023-05-17-13-24-23.png)

根据图例，来配置，注意，激活insecure，因为我们是自签名证书

<!-- ![](imgs/2023-05-17-13-24-53.png) -->
![](imgs/2023-05-17-14-35-06.png)

详细配置里面，我们disable全部功能，因为我们不需要satellite来帮助我们部署服务器。我们让这个URL一直有效。

![](imgs/2023-05-17-13-28-04.png)


点击生成以后，就得到一个命令，复制下来，保存起来。

![](imgs/2023-05-17-13-28-36.png)


<!-- ![](imgs/2023-05-17-14-33-41.png) -->

有了命令，我们就找一台rhel，来试试。

```bash
# on client host

curl -sS --insecure 'https://panlab-satellite-server.infra.wzhlab.top/register?activation_keys=demo-activate&location_id=2&organization_id=1&setup_insights=false&setup_remote_execution=false&setup_remote_execution_pull=false&update_packages=false' -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo0LCJpYXQiOjE2ODQzMDU1MTYsImp0aSI6IjdiODBkNzdmMjVjYzY1MDZjODQ3OGI2Y2VjNzRkZWZjOGM2YjAyMDUxMDQ4YTcyYTJlMWE1YzRiNTgyMjE5NzAiLCJzY29wZSI6InJlZ2lzdHJhdGlvbiNnbG9iYWwgcmVnaXN0cmF0aW9uI2hvc3QifQ.EVXyW9gjWyAQIFYUxnwwdxAigrPmUo_XYWnqn-Wh1Fw' | bash

# #
# # Running registration
# #
# Updating Subscription Management repositories.
# Unable to read consumer identity

# This system is not registered with an entitlement server. You can use subscription-manager to register.

# Error: There are no enabled repositories in "/etc/yum.repos.d", "/etc/yum/repos.d", "/etc/distro.repos.d".
# The system has been registered with ID: e9d03372-d3f4-4970-bb38-3a2282458e29
# The registered system name is: panlab-satellite-client
# Installed Product Current Status:
# Product Name: Red Hat Enterprise Linux for x86_64
# Status:       Subscribed

# # Running [panlab-satellite-client] host initial configuration
# Refreshing subscription data
# All local data refreshed
# Host [panlab-satellite-client] successfully configured.
# Successfully updated the system facts.

subscription-manager status
# +-------------------------------------------+
#    System Status Details
# +-------------------------------------------+
# Overall Status: Current

# System Purpose Status: Not Specified

subscription-manager release --list
# +-------------------------------------------+
#           Available Releases
# +-------------------------------------------+
# 8.6

subscription-manager release --set=8.6

subscription-manager config
# [server]
#    hostname = panlab-satellite-server.infra.wzhlab.top
# ......
# [rhsm]
#    auto_enable_yum_plugins = [1]
#    baseurl = https://panlab-satellite-server.infra.wzhlab.top/pulp/content
# ......

dnf repolist
# Updating Subscription Management repositories.
# repo id                                                                   repo name
# rhel-8-for-x86_64-appstream-rpms                                          Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)
# rhel-8-for-x86_64-baseos-rpms                                             Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs)

dnf makecache
# Updating Subscription Management repositories.
# Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs)                                                                                       63 kB/s | 4.1 kB     00:00
# Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)                                                                                    65 kB/s | 4.5 kB     00:00
# Metadata cache created.

subscription-manager repos
# +----------------------------------------------------------+
#     Available Repositories in /etc/yum.repos.d/redhat.repo
# +----------------------------------------------------------+
# Repo ID:   rhel-8-for-x86_64-baseos-rpms
# Repo Name: Red Hat Enterprise Linux 8 for x86_64 - BaseOS (RPMs)
# Repo URL:  https://panlab-satellite-server.infra.wzhlab.top/pulp/content/My_Organization/Library/content/dist/rhel8/8.6/x86_64/baseos/os
# Enabled:   1

# Repo ID:   rhel-8-for-x86_64-appstream-rpms
# Repo Name: Red Hat Enterprise Linux 8 for x86_64 - AppStream (RPMs)
# Repo URL:  https://panlab-satellite-server.infra.wzhlab.top/pulp/content/My_Organization/Library/content/dist/rhel8/8.6/x86_64/appstream/os
# Enabled:   1


```

<!-- ![](imgs/2023-05-17-14-56-51.png) -->

<!-- ![](imgs/2023-05-17-14-58-08.png) -->

我们回到active key，可以看到已经激活的 repo

![](imgs/2023-05-17-15-00-11.png)

然后看到，我们没有配置host collection，所以这里也是空的。

![](imgs/2023-05-17-15-00-22.png)

最后，我们在active key的host列表中，看到了我们刚才的主机。

![](imgs/2023-05-17-15-00-55.png)

点进去看看，可以看到主机的rpm的安全问题，satellite已经能够看到。

![](imgs/2023-05-17-15-09-56.png)

问题那么多，我们更新一下看看
```bash
# on satellite-client
dnf update -y

```
哈哈，问题都解决了。

![](imgs/2023-05-17-18-18-48.png)

我们能看到，已经使用了一个订阅

![](imgs/2023-05-17-15-14-52.png)

在订阅详细信息里面，也能看到一个activation key

![](imgs/2023-05-17-15-15-23.png)

订阅包含的，使用的产品内容就是baseos, appstream

![](imgs/2023-05-17-15-15-46.png)

主机列表多了我们刚才激活的主机。

![](imgs/2023-05-17-15-16-44.png)

<!-- 我们查看capsule的使用资源情况。

![](imgs/2023-05-17-15-17-41.png) -->

# 增加订阅数量

如果我们多买了一些订阅，怎么添加数量呢？这里，我们就模拟增加1个订阅的场景。

我们访问redhat portal，点击之前创建的订阅分配。

![](imgs/2023-05-17-15-18-46.png)

调整数量为 2

![](imgs/2023-05-17-15-26-21.png)

回到satellite里面，我们维护一下我们的manifect

![](imgs/2023-05-17-15-27-14.png)

点击刷新，他会在线更新

![](imgs/2023-05-17-15-28-45.png)

更新完成以后，数量就变成 2 了。

![](imgs/2023-05-17-15-29-32.png)

# 超用会发生什么

我们回复订阅分配为 1 ，然后在第二台主机上激活订阅，会发生什么呢？

```bash
# on client-02 , to try over use
curl -sS --insecure 'https://panlab-satellite-server.infra.wzhlab.top/register?activation_keys=demo-activate&location_id=2&organization_id=1&setup_insights=false&setup_remote_execution=false&setup_remote_execution_pull=false&update_packages=false' -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo0LCJpYXQiOjE2ODQzMDU1MTYsImp0aSI6IjdiODBkNzdmMjVjYzY1MDZjODQ3OGI2Y2VjNzRkZWZjOGM2YjAyMDUxMDQ4YTcyYTJlMWE1YzRiNTgyMjE5NzAiLCJzY29wZSI6InJlZ2lzdHJhdGlvbiNnbG9iYWwgcmVnaXN0cmF0aW9uI2hvc3QifQ.EVXyW9gjWyAQIFYUxnwwdxAigrPmUo_XYWnqn-Wh1Fw' | bash
# #
# # Running registration
# #
# Updating Subscription Management repositories.
# Unable to read consumer identity

# This system is not registered with an entitlement server. You can use subscription-manager to register.

# Error: There are no enabled repositories in "/etc/yum.repos.d", "/etc/yum/repos.d", "/etc/distro.repos.d".
# The system has been registered with ID: 43e38f76-2416-49db-890f-1a3ad3973828
# The registered system name is: satellite-client-02
# Installed Product Current Status:
# Product Name: Red Hat Enterprise Linux for x86_64
# Status:       Not Subscribed

# Unable to find available subscriptions for all your installed products.

subscription-manager list --consumed
# No consumed subscription pools were found.

subscription-manager repos
# This system has no repositories available through subscriptions.

subscription-manager status
# +-------------------------------------------+
#    System Status Details
# +-------------------------------------------+
# Overall Status: Invalid

# Red Hat Enterprise Linux for x86_64:
# - Not supported by a valid subscription.

# System Purpose Status: Not Specified
```
我们可以看到，订阅没有激活。我们确认一下，在订阅里面看，消耗量为 1

![](imgs/2023-05-17-19-00-41.png)

但是在activation key 里面，host 为2

![](imgs/2023-05-17-19-10-32.png)

不过，这个host list里面，有一个主机没有激活。

![](imgs/2023-05-17-19-12-23.png)

# 激活 Simple Content Access (SCA)
<!-- if we enable SCA, and limit the active key host number, what happend? -->

我们激活SCA，并限制 activation key 的 host 数量，用这种方法，来平衡使用方便和订阅不要超用。

激活 SCA

![](imgs/2023-05-17-20-05-11.png)

限制host 数量为1
![](imgs/2023-05-17-20-05-56.png)


我们在第二台主机上在激活试试
```bash
# on client-02 , to try over use
curl -sS --insecure 'https://panlab-satellite-server.infra.wzhlab.top/register?activation_keys=demo-activate&location_id=2&organization_id=1&setup_insights=false&setup_remote_execution=false&setup_remote_execution_pull=false&update_packages=false' -H 'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjo0LCJpYXQiOjE2ODQzMDU1MTYsImp0aSI6IjdiODBkNzdmMjVjYzY1MDZjODQ3OGI2Y2VjNzRkZWZjOGM2YjAyMDUxMDQ4YTcyYTJlMWE1YzRiNTgyMjE5NzAiLCJzY29wZSI6InJlZ2lzdHJhdGlvbiNnbG9iYWwgcmVnaXN0cmF0aW9uI2hvc3QifQ.EVXyW9gjWyAQIFYUxnwwdxAigrPmUo_XYWnqn-Wh1Fw' | bash
# #
# # Running registration
# #
# Updating Subscription Management repositories.
# Unable to read consumer identity

# This system is not registered with an entitlement server. You can use subscription-manager to register.

# Error: There are no enabled repositories in "/etc/yum.repos.d", "/etc/yum/repos.d", "/etc/distro.repos.d".
# Max Hosts (1) reached for activation key 'demo-activate' (HTTP error code 409: Conflict)

```
激活失败。

# end