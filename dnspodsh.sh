#!/bin/bash

##############################
# dnspodsh v0.5
# 基于dnspod api构架的bash ddns客户端
# 修改者：sookey@gmail.com
# 原作者：zrong(zengrong.net)
# 详细介绍：http://zengrong.net/post/1524.htm
# 创建日期：2012-02-13
# 更新日期：2018-03-29
##############################

# 填自己的配置
target_file='name.csv'
# 填自己的token
login_token='123456,sdfasdfgasgdadfasdfasdfasdfasdf'
format="json"
lang="en"
userAgent="dnspodsh/0.5(sookey@gmail.com)"
commonPost="login_token=$login_token&format=$format&lang=$lang"
apiUrl='https://dnsapi.cn/'
# logfile  填自己的路径
logDir='.'
logFile=$logDir'/dnspodapi.log'

# 检测ip地址是否符合要求
checkip()
{
        # ipv4地址
        if [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]];then
                return 0
        # ipv6地址
#       elif [[ "$1" =~ ^([\da-fA-F]{1,4}:){7}[\da-fA-F]{1,4}$|^:((:[\da-fA-F]{1,4}){1,6}|:)$|^[\da-fA-F]{1,4}:((:[\da-fA-F]{1,4}){1,5}|:)$|^([\da-fA-F]{1,4}:){2}((:[\da-fA-F]{1,4}){1,4}|:)$|^([\da-fA-F]{1,4}:){3}((:[\da-fA-F]{1,4}){1,3}|:)$|^([\da-fA-F]{1,4}:){4}((:[\da-fA-F]{1,4}){1,2}|:)$|^([\da-fA-F]{1,4}:){5}:([\da-fA-F]{1,4})?$|^([\da-fA-F]{1,4}:){6}:$ ]];then
#               return 0
        fi
        return 1
}
writeLog()
{
        if [ -w $logDir ];then
                local pre=`date`
                for arg in $@;do
                        pre=$pre'\t'$arg
                done
                echo -e $pre>>$logFile
        fi
        echo -e $1
}
# 获取返回代码是否正确
# $1 要检测的字符串，该字符串包含{status:{code:1}}形式，代表DNSPodAPI返回正确
# $2 是否要停止程序，因为dnspod在代码错误过多的情况下会封禁账号
checkStatusCode()
{
        if [[ "$1" =~ \{\"status\":\{[^}{]*\"code\":\"1\"[^}]*\} ]]; then
            return 0
        fi
        writeLog "DNSPOD return error:$1"
        # 根据参数需求退出程序
        if [ -n "$2" ] && [ "$2" -eq 1 ];then
                writeLog 'exit dnspodsh'
                exit 1
        fi
}

getUrl()
{
        curl -s -A $userAgent -d $commonPost$2 $apiUrl$1
}

# 通过key得到找到一个JSON对象字符串中的值
getDataByKey()
{
        local s='s/{[^}]*"'$2'":["]*\('$(getRegexp $2)'\)["]*[^}]*}/\1/'
        #echo '拼合成的regexp:'$s
        echo $1|sed $s
}

# 根据key返回要获取的正则表达式
getRegexp()
{
        case $1 in
                'value') echo '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}';;
                'type') echo '[A-Z]\+';;
                'name') echo '[-_.A-Za-z0-9*]\+';;
                'ttl'|'id') echo '[0-9]\+';;
                'line') echo '[^"]\+';;
        esac
}

# 通过一个JSON key名称，获取一个{}包围的JSON对象字符串
# $1 要搜索的key名称
# $2 要搜索的对应值
getJSONObjByKey()
{
        grep -o '{[^}{]*"'$1'":"'$2'"[^}]*}'
}

# 获取A记录类型的域名信息
# 对于其它记录，同样的名称可以对应多条记录，因此使用getJSONObjByKey可能获取不到需要的数据
getJSONObjByARecord()
{
        grep -o '{[^}{]*"name":"'$1'"[^}]*"type":"A"[^}]*}'
}

# 根据域名id获取记录列表
# $1 域名id
getRecordList()
{
        getUrl "Record.List" "&domain_id=$1&offset=0&length=20"
}
getDomainList()
{
        getUrl "Domain.List" "&type=all&offset=0&length=10"
}
# 设置记录
setRecord()
{
        writeLog "set domain $3.$8 to new ip:$7"
        local subDomain=$3
        # 由于*会被扩展，在最后一步将转义的\*替换成*
        if [ "$subDomain" = '\*' ];then
            subDomain='*'
        fi
        local request="&domain_id=$1&record_id=$2&sub_domain=$subDomain&record_type=$4&record_line=$5&ttl=$6&value=$7"

        local saveResult=$(getUrl 'Record.Modify' "$request")
        # 检测返回是否正常，但即使不正常也不退出程序
        if checkStatusCode "$saveResult" 0;then
            writeLog "set record $3.$8 success."
        fi
        #getUrl 'Record.Modify' "&domain_id=$domainid&record_id=$recordid&sub_domain=$recordName&record_type=$recordtype&record_line=$recordline&ttl=$recordttl&value=$newip"
        unset changeRecords
}

domainList=$(egrep -v '^ *#' $target_file | awk -F, '{print $NF}' | sort | uniq)

for domain in $domainList
do
    # 用于记录被改变的记录
    unset changedRecords

    # 从DNSPod获取最新的域名列表
    domainListInfo=$(getDomainList)
    domainName=$domain
    domainInfo=$(echo $domainListInfo|getJSONObjByKey 'name' $domainName) 
    domainid=$(getDataByKey "$domainInfo" 'id')
    recordList=$(getRecordList $domainid)    

    if [ -z "$recordList" ];then
        writeLog 'DNSPOD tell me record list null,waiting...'
        return 1
    fi
    checkStatusCode "$recordList" 1

    for sub_all in $(egrep -v '^ *#' $target_file | grep ",$domain")
    do
        subdomain=$(echo $sub_all | awk -F',' '{print $2}')
        if [ "$subdomain" = '*' ];then
            subdomain='\*'
        fi
        # 从dnspod获取要设置的子域名记录的信息
        recordInfo=$(echo $recordList|getJSONObjByARecord $subdomain)

        # 从dnspod获取要设置的子域名的ip
        oldip=$(getDataByKey "$recordInfo" 'value')
        # 检测获取到的旧ip地址是否符合ip规则
        if ! checkip "$oldip";then
            writeLog 'get old ip error!it is "$oldid".waiting...'
            continue
        fi

        newip=$(echo $sub_all | awk -F',' '{print $4}')

        if [ "$newip" != "$oldip" ];then
            recordid=$(getDataByKey "$recordInfo" 'id')
            recordName=$subdomain
            recordTtl=$(echo $sub_all | awk -F',' '{print $6}')
            recordType=$(echo $sub_all | awk -F',' '{print $1}')

            # 由于从服务器获取的线路是utf编码，目前无法知道如何转换成中文，因此在这里写死。dnspod中免费用户的默认线路的名称就是“默认”
            #recordLine=$(getDataByKey "$recordInfo" 'line')
            recordLine='默认'
    
            # 判断取值是否正常，如果值为空就不处理
            if [ -n "$recordid" ] && [ -n "$recordTtl" ] && [ -n "$recordType" ]; then
                # 使用数组记录需要修改的子域名的所有值
                # 这里一共有8个参数，与setRecord中的参数对应
                changedRecords=($domainid $recordid $recordName $recordType $recordLine $recordTtl $newip $domainName)
                if (( ${#changedRecords[@]} == 8 ));then
                    #echo ${changedRecords[@]}
                    writeLog "$recordName.$domainName  ip is changed,new ip is:$newip"
                    setRecord ${changedRecords[@]}
                fi
            fi
        fi
    done
done
