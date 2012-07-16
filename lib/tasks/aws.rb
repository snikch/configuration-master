require "uri"
require "net/http"
require "ops/aws_settings"
require "ops/stacks"
require "ops/puppet_bootstrap"
require "ops/rolling_upgrade"
require "ops/bootstrap_package"
require "ops/bootstrap_url"
require "go/system_integration_pipeline"
require "go/production_deploy_pipeline"

namespace :aws do
  SETTINGS = Ops::AWSSettings.load

  desc "creates the CI environment"
  task :ci_start => ["clean", "package:puppet"] do
    puppet_bootstrap = Ops::PuppetBootstrap.new(:role => "buildserver",
                                                :boot_package_url => setup_bootstrap,
                                                :deploy_key_url => key_bootstrap)
    stacks = Ops::Stacks.new("ci-environment",
                             "KeyName" => SETTINGS.aws_ssh_key_name,
                             "BootScript" => puppet_bootstrap.script)

    puts "booting the CI environment"
    stacks.create do |stack|
      instance = stack.outputs.find { |output| output.key == "PublicAddress" }
      puts "your CI server's address is http://#{instance.value}:8153"
    end
  end

  desc "stops the CI environment"
  task :ci_stop do
    puts "stopping the CI environment"
    Ops::Stacks.new("ci-environment").delete!
  end

  desc "creates a new instance of the application server"
  task :build_appserver => BUILD_DIR do
    pipeline = Go::SystemIntegrationPipeline.new
    puppet_bootstrap = Ops::PuppetBootstrap.new(:role => "appserver",
                                                :facter => { :artifact => pipeline.aws_twitter_feed_artifact },
                                                :boot_package_url => pipeline.configuration_master_artifact)

    stack = Ops::Stacks.new("appserver-validation",
                            "KeyName" => SETTINGS.aws_ssh_key_name,
                            "BootScript" => puppet_bootstrap.script)
    stack.delete!
    stack.create

    hostname = stack.instances.first.url
    File.open("#{BUILD_DIR}/app-url", "w") { |file| file.write(hostname) }
  end

  desc "creates an image of an existing appserver instance"
  task :create_image => BUILD_DIR do
    stack = Ops::Stacks.new("appserver-validation")
    image_name = ENV["GO_PIPELINE_COUNTER"]+"-"+ENV["GO_REVISION"]+"-#{rand(999)}"
    image_id = stack.instances.first.create_image(image_name)

    File.open("#{BUILD_DIR}/image", "w") { |file| file.write(image_id) }

    stack.delete!
  end

  desc "updates the production environment with a new appserver image"
  task :deploy_to_production do
    image_id = Go::ProductionDeployPipeline.new.upstream_artifact
    puts "updating production configuration with image '#{image_id}'"

    stack = Ops::Stacks.new("production-environment",
                            "KeyName" => SETTINGS.aws_ssh_key_name,
                            "ImageId" => image_id)
    stack.create_or_update
  end

  desc "replaces the existing production servers with the new image"
  task :roll_new_version do
    image_id = Go::ProductionDeployPipeline.new.upstream_artifact
    puts "rolling image #{image_id} into production"

    upgrade = Ops::RollingUpgrade.new(image_id)
    upgrade.run

    puts "new version updated successfuly"
  end

  def setup_bootstrap
    bucket_name = "learnaby-bootstrap-bucket-#{SETTINGS.aws_ssh_key_name}"
    Ops::BootstrapPackage.new("#{BUILD_DIR}/#{BOOTSTRAP_FILE}", bucket_name).url
  end

  def key_bootstrap
    bucket_name = "learnable-credentials"
    Ops::BootstrapUrl.new("learnable-deploy-key.rsa", bucket_name).url
  end
end
