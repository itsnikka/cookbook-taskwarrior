include_recipe "apt"
include_recipe "git"
include_recipe "build-essential"
include_recipe "cmake"
include_recipe "perl"
include_recipe "python"
include_recipe "runit"

%w{ libgnutls-dev libreadline6 uuid-dev }.each do |pkg|
  package pkg
end

git "#{Chef::Config[:file_cache_path]}/taskd.git" do
  repository node["taskwarrior"]["server"]["git_repository"]
  reference node["taskwarrior"]["server"]["git_revision"]
  action :sync
  notifies :run, "bash[Install taskd]", :immediately
end

bash "Install taskd" do
  user "root"
  cwd "#{Chef::Config[:file_cache_path]}/taskd.git"
  code <<-EOH
  cmake .
  make
  make install
  EOH
  action :nothing
  notifies :restart, "runit_service[taskd]", :delayed
end

user "taskd" do
  system true
  home node["taskwarrior"]["server"]["home"]
  shell "/bin/false"
end

directory node["taskwarrior"]["server"]["home"] do
  owner "taskd"
  group "taskd"
  mode 00644
  recursive true
end

directory node["taskwarrior"]["server"]["data_dir"] do
  owner "taskd"
  group "taskd"
  mode 00644
  recursive true
end

template "#{node["taskwarrior"]["server"]["data_dir"]}/config" do
  source "taskd.config.erb"
  owner "taskd"
  group "taskd"
  mode 00644
  variables({
    :confirmation => node["taskwarrior"]["server"]["confirmation"],
    :extensions => node["taskwarrior"]["server"]["extensions"],
    :ip_log => node["taskwarrior"]["server"]["ip_log"],
    :log => node["taskwarrior"]["server"]["log"],
    :queue_size=> node["taskwarrior"]["server"]["queue_size"],
    :request_limit=> node["taskwarrior"]["server"]["request_limit"],
    :root => node["taskwarrior"]["server"]["data_dir"],
    :server => node["taskwarrior"]["server"]["link"]
  })
  notifies :restart, "runit_service[taskd]", :delayed
end

if node["taskwarrior"]["server"]["initialized"]  == false then
  bash "Initialize database" do
    user "root"
    cwd node["taskwarrior"]["server"]["home"]
    code <<-EOH
    taskd init --data #{node["taskwarrior"]["server"]["data_dir"]}
    EOH
  end

  node.set["taskwarrior"]["server"]["initialized"] == true
end

package "gnutls-bin"

bash "Generating CA key" do
  user "root"
  cwd node["taskwarrior"]["server"]["home"]
  code <<-EOH
    certtool --generate-privkey --outfile ca.key.pem
  EOH
  not_if {::File.exists?("#{node["taskwarrior"]["server"]["home"]}/ca.key.pem")}
end

template "#{node["taskwarrior"]["server"]["home"]}/ca.info" do
  source "ca.info.erb"
  owner "root"
  group "root"
  mode 00600
  variables({
    :organization => "Lol chef"
  })
  not_if {::File.exists?("#{node["taskwarrior"]["server"]["home"]}/ca.cert.pem")}
  notifies :run, "bash[Generating CA Cert]", :immediately
end

bash "Generating CA Cert" do
  user "root"
  cwd node["taskwarrior"]["server"]["home"]
  code <<-EOH
    certtool --generate-self-signed \
    --load-privkey ca.key.pem \
    --template ca.info \
    --outfile ca.cert.pem
    rm ca.info
  EOH
  action :nothing
end

runit_service "taskd" do
  options({
    :user => "taskd",
    :data_dir => node["taskwarrior"]["server"]["data_dir"]
  })
  default_logger true
end
