#!/bin/bash -xe

##SM: 
#This userdata will push to each VM/Node via nova API.
#See deploy.sh, it uses "jiocloud.apply_resources apply" to create VM/Node and push userdata.
#You can see "apply_resources.py" script in github project "python-jiocloud"

cat <<EOF >userdata.txt
#!/bin/bash
date
set -x
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
export layout="${layout}"
release="\$(lsb_release -cs)"
if [ -n "${git_protocol}" ]; then
  export git_protocol="${git_protocol}"
fi
export no_proxy="127.0.0.1,169.254.169.254,localhost,consul,jiocloud.com"
echo no_proxy="'127.0.0.1,169.254.169.254,localhost,consul,jiocloud.com'" >> /etc/environment
if [ -n "${env_http_proxy}" ]
then
	export http_proxy=${env_http_proxy}
	echo http_proxy="'${env_http_proxy}'" >> /etc/environment
fi
if [ -n "${env_https_proxy}" ]
then
	export https_proxy=${env_https_proxy}
	export ETCD_DISCOVERY_PROXY=${env_https_proxy}
	echo ETCD_DISCOVERY_PROXY="'${env_https_proxy}'" >> /etc/environment
	echo https_proxy="'${env_https_proxy}'" >> /etc/environment
fi
wget -O puppet.deb -t 2 -T 30 http://apt.puppetlabs.com/puppetlabs-release-\${release}.deb
if [ "${env}" == "at" ]
then
	jiocloud_repo_deb_url=http://jiocloud.rustedhalo.com/ubuntu/jiocloud-apt-\${release}-testing.deb
else
	jiocloud_repo_deb_url=http://jiocloud.rustedhalo.com/ubuntu/jiocloud-apt-\${release}.deb
fi
wget -O jiocloud.deb -t 2 -T 30 \${jiocloud_repo_deb_url}
dpkg -i puppet.deb jiocloud.deb
if http_proxy= wget -t 2 -T 30 -O internal.deb http://apt.internal.jiocloud.com/internal.deb
then
       dpkg -i internal.deb
fi
apt-get update
apt-get install -y puppet software-properties-common puppet-jiocloud jiocloud-ssl-certificate
if [ -n "${python_jiocloud_source_repo}" ]; then
  apt-get install -y python-pip python-jiocloud python-dev libffi-dev libssl-dev git
  pip install -e "${python_jiocloud_source_repo}@${python_jiocloud_source_branch}#egg=jiocloud"
fi
if [ -n "${puppet_modules_source_repo}" ]; then
  apt-get install -y git
  git clone ${puppet_modules_source_repo} /tmp/rjil
  if [ -n "${puppet_modules_source_branch}" ]; then
    pushd /tmp/rjil
    git checkout ${puppet_modules_source_branch}
    popd
  fi
  if [ -n "${pull_request_id}" ]; then
    pushd /tmp/rjil
    git fetch origin pull/${pull_request_id}/head:test_${pull_request_id}
    git config user.email "testuser@localhost.com"
    git config user.name "Test User"
    git merge -m 'Merging Pull Request' test_${pull_request_id}
    popd
  fi
  time gem install librarian-puppet-simple --no-ri --no-rdoc;
  mkdir -p /etc/puppet/manifests.overrides
  cp /tmp/rjil/site.pp /etc/puppet/manifests.overrides/
  mkdir -p /etc/puppet/hiera.overrides
  sed  -i "s/  :datadir: \/etc\/puppet\/hiera\/data/  :datadir: \/etc\/puppet\/hiera.overrides\/data/" /tmp/rjil/hiera/hiera.yaml
  cp /tmp/rjil/hiera/hiera.yaml /etc/puppet
  cp -Rvf /tmp/rjil/hiera/data /etc/puppet/hiera.overrides
  mkdir -p /etc/puppet/modules.overrides/rjil
  cp -Rvf /tmp/rjil/* /etc/puppet/modules.overrides/rjil/
  time librarian-puppet install --puppetfile=/tmp/rjil/Puppetfile --path=/etc/puppet/modules.overrides
  puppet apply -e "ini_setting { modulepath: path => \"/etc/puppet/puppet.conf\", section => main, setting => modulepath, value => \"/etc/puppet/modules.overrides:/etc/puppet/modules\" }"
  puppet apply -e "ini_setting { manifestdir: path => \"/etc/puppet/puppet.conf\", section => main, setting => manifestdir, value => \"/etc/puppet/manifests.overrides\" }"
fi
sudo mkdir -p /etc/facter/facts.d
echo 'consul_discovery_token='${consul_discovery_token} > /etc/facter/facts.d/consul.txt
echo 'current_version='${BUILD_NUMBER} > /etc/facter/facts.d/current_version.txt
echo 'env='${env} > /etc/facter/facts.d/env.txt
echo 'cloud_provider='${cloud_provider} > /etc/facter/facts.d/cloud_provider.txt
while true
do
    # first install all packages to make the build as fast as possible
    puppet apply --detailed-exitcodes \`puppet config print manifestdir\`/site.pp --tags package
    ret_code_package=\$?
    # now perform base config
    (echo 'File<| title == "/etc/consul" |> { purge => false }'; echo 'include rjil::jiocloud' ) | puppet apply --detailed-exitcodes --debug
    ret_code_jio=\$?
    if [[ \$ret_code_jio = 1 || \$ret_code_jio = 4 || \$ret_code_jio = 6 || \$ret_code_package = 1 || \$ret_code_package = 4 || \$ret_code_package = 6 ]]
    then
        echo "Puppet failed. Will retry in 5 seconds"
        sleep 5
    else
        break
    fi
done
date
EOF
