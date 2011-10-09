require 'bundler/capistrano'

set :application, "othereplies"
set :repository,  "git@github.com:mattb/othereplies.git"
set :deploy_to, "/var/www/replies.hackdiary.com"
set :user, "mattb"

set :scm, :git
set :deploy_via, :remote_cache

ssh_options[:forward_agent] = true
default_run_options[:pty] = true

role :web, "www.hackdiary.com"                          # Your HTTP server, Apache/etc
role :app, "www.hackdiary.com"                          # This may be the same as your `Web` server
role :db,  "www.hackdiary.com", :primary => true # This is where Rails migrations will run

# If you are using Passenger mod_rails uncomment this:
namespace :deploy do
   task :start do ; end
   task :stop do ; end
   task :restart, :roles => :app, :except => { :no_release => true } do
     run "mkdir #{release_path}/lib ; ln -nfs #{shared_path}/system/twitter-config.rb #{release_path}/lib/"
     run "#{try_sudo} touch #{File.join(current_path,'tmp','restart.txt')}"
   end
end

namespace :foreman do
  desc "Export the Procfile to Ubuntu's upstart scripts"
  task :export, :roles => :app do
    run "cd #{release_path} && sudo bundle exec foreman export upstart /etc/init -a #{application} -u #{user} -l #{shared_path}/log"
  end
  
  desc "Start the application services"
  task :start, :roles => :app do
    sudo "start #{application}"
  end

  desc "Stop the application services"
  task :stop, :roles => :app do
    sudo "stop #{application}"
  end

  desc "Restart the application services"
  task :restart, :roles => :app do
    run "sudo start #{application} || sudo restart #{application}"
  end
end

after "deploy:update", "foreman:export"
after "deploy:update", "foreman:restart"
before "foreman:export", "monitor:jar"

namespace :monitor do
  task :jar, :roles => :app do
    servers = find_servers :roles => :app
    servers.each do |server|
      `sbt one-jar && rsync -z target/scala-2.9.1/othereplies_2.9.1-0.1-one-jar.jar #{user}@#{server}:#{shared_path}/system/`
    end
  end
end
