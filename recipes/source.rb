include_recipe "apt"
include_recipe "git"
include_recipe "build-essential"
include_recipe "cmake"

package "uuid-dev"

git "#{Chef::Config[:file_cache_path]}/task.git" do
  repository node["taskwarrior"]["source"]["git_repository"]
  reference node["taskwarrior"]["source"]["git_revision"]
  action :sync
  notifies :run, "bash[Install taskwarrior]"
end

bash "Install taskwarrior" do
  user "root"
  cwd "#{Chef::Config[:file_cache_path]}/task.git"
  code <<-EOH
  cmake .
  make
  make install
  EOH
  action :nothing
end
