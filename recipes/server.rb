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
  shell "/bin/bash"
end

group "log" do
  members "taskd"
  append true
end

directory node["taskwarrior"]["server"]["home"] do
  owner "taskd"
  group "taskd"
  mode 00744
  recursive true
end

directory node["taskwarrior"]["server"]["data_dir"] do
  owner "taskd"
  group "taskd"
  mode 00744
  recursive true
end

directory node["taskwarrior"]["server"]["log_dir"] do
  owner "taskd"
  group "taskd"
  mode 00744
  recursive true
end

bash "Initialize database" do
  user "taskd"
  cwd node["taskwarrior"]["server"]["home"]
  code <<-EOH
  taskd init --data #{node["taskwarrior"]["server"]["data_dir"]}
  EOH
  not_if { ::File.exists?("#{node["taskwarrior"]["server"]["data_dir"]}/org") }
end

include_recipe "taskwarrior::certs"

template "#{node["taskwarrior"]["server"]["data_dir"]}/config" do
  source "taskd.config.erb"
  owner "taskd"
  group "taskd"
  mode 00644
  variables({
    :confirmation => node["taskwarrior"]["server"]["confirmation"],
    :extensions => node["taskwarrior"]["server"]["extensions"],
    :ip_log => node["taskwarrior"]["server"]["ip_log"],
    :log => node["taskwarrior"]["server"]["log_file"],
    :queue_size=> node["taskwarrior"]["server"]["queue_size"],
    :request_limit=> node["taskwarrior"]["server"]["request_limit"],
    :root => node["taskwarrior"]["server"]["data_dir"],
    :server => node["taskwarrior"]["server"]["link"],
    :server_cert => "#{node["taskwarrior"]["server"]["keys_dir"]}/server.cert.pem",
    :server_crl => "#{node["taskwarrior"]["server"]["keys_dir"]}/server.crl.pem",
    :server_key => "#{node["taskwarrior"]["server"]["keys_dir"]}/server.key.pem",
    :ca_cert => "#{node["taskwarrior"]["server"]["keys_dir"]}/ca.cert.pem",
    :client_allow => node["taskwarrior"]["server"]["clients"]
  })
  notifies :restart, "runit_service[taskd]", :delayed
end


runit_service "taskd" do
  options({
    :user => "taskd",
    :data_dir => node["taskwarrior"]["server"]["data_dir"]
  })
  log false
end
