#!/bin/bash -xe

. $(dirname $0)/common.sh

# If these aren't yet set (from credentials file, typically),
if [ -z "${consul_discovery_token}" ]
then
    consul_discovery_token=$(curl http://consuldiscovery.linux2go.dk/new)
fi

##SM:
#make usedata by running the script build_scripts/make_userdata.sh
#This creates a userdata.txt
. $(dirname $0)/make_userdata.sh

##SM:
#Starting point: Create VMs/Nodes/hosts
#Create VMs/Nodes and push userdata (userdata.txt) via nova API
#You can see "apply_resources.py" script and "apply" action in github project "python-jiocloud"
#It get cluster config (number of VMs/Nodes and its config) from environment/${layout}.yaml
#Here "project_tag" means "BUILD_NUMBER" and defined in "build_scripts/common.sh"
#Here "mappings_arg" is "--mappings=environment/${cloud_provider}.map.yaml"
time python -m jiocloud.apply_resources apply ${EXTRA_APPLY_RESOURCES_OPTS} --key_name=${KEY_NAME:-soren} --project_tag=${project_tag} ${mappings_arg} environment/${layout}.yaml userdata.txt

##SM:
#In a loop, Try to find the IP of "consul_bootstrap_node" node and SSH to it and run "jiocloud.orchestrate ping"
#Here "jiocloud.utils.py" script and "get_ip_of_node" action are defined in the github project "python-jiocloud".
#Here "consul_bootstrap_node" is the name of the node whoes ip need to find. We use nova api to find server and IP.
#Here "jiocloud.orchestrate.py" script and "ping" action are defined in the github project "python-jiocloud".
#"ping" action make a consul API call.
time $timeout 1200 bash -c 'while ! bash -c "ip=$(python -m jiocloud.utils get_ip_of_node ${consul_bootstrap_node:-etcd1}_${project_tag});ssh -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no \${ssh_user:-jenkins}@\${ip} python -m jiocloud.orchestrate ping"; do sleep 5; done'

##SM:
#Get the IP of "consul_bootstrap_node" node using nova API.
ip=$(python -m jiocloud.utils get_ip_of_node ${consul_bootstrap_node:-etcd1}_${project_tag})

##SM:
#ssh to "consul_bootstrap_node" node and execute the script "jiocloud.orchestrate.py" with action "trigger_update" and BUILD_NUMBER.
#"trigger_update" will update the value of the consul key "current_version" with BUILD_NUMBER.
#"trigger_update" action make a consul API call.
time $timeout 600 bash -c "while ! ssh -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${ssh_user:-jenkins}@${ip} python -m jiocloud.orchestrate trigger_update ${BUILD_NUMBER}; do sleep 5; done"

##SM:
#Verify that all VMs/Nodes/hosts defined in the environment/${layout}.yaml are got created successfully.
#Here "jiocloud.apply_resources.py" script and "list" action are defined in the github project "python-jiocloud".
#First, the action "list" read all VMs/Nodes/hosts defined in the environment/${layout}.yaml
#Then, ssh to "consul_bootstrap_node" node and execute the script "jiocloud.orchestrate.py" with action "verify_hosts" and BUILD_NUMBER.
#Then, the "verify_hosts" action make a consul API call and get all host version records and compare with hosts list parsed from environment/${layout}.yaml.
time $timeout 3000 bash -c "while ! python -m jiocloud.apply_resources list --project_tag=${project_tag} environment/${layout}.yaml | sed -e 's/_/-/g' | ssh -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${ssh_user:-jenkins}@${ip} python -m jiocloud.orchestrate verify_hosts ${BUILD_NUMBER} ; do sleep 5; done"

##SM:
#ssh to "consul_bootstrap_node" node and execute the script "jiocloud.orchestrate.py" with action "check_single_version" and BUILD_NUMBER.
#Here, the "check_single_version" action make consul API call and get all host version records and check whether BUILD_NUMBER exist or not.
time $timeout 2400 bash -c "while ! ssh -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${ssh_user:-jenkins}@${ip} python -m jiocloud.orchestrate check_single_version -v ${BUILD_NUMBER} ; do sleep 5; done"

##SM:
#ssh to "consul_bootstrap_node" node and execute the script "jiocloud.orchestrate.py" with action "get_failures" and --hosts.
#Here, the "get_failures" action make a consul API call and gets critical/failure and warning health state and rtuen True if no failure and warning.
time $timeout 600 bash -c "while ! ssh -o ServerAliveInterval=30 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no ${ssh_user:-jenkins}@${ip} python -m jiocloud.orchestrate get_failures --hosts; do sleep 5; done"



