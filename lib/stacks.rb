require "aws-sdk"

class Stacks
  def initialize data
    @data = data
  end

  def create &block
    cloud_formation = AWS::CloudFormation.new
    stack = cloud_formation.stacks[name]
    (puts("the CI environment exists already. Nothing to do") and return) if stack.exists?

    puts "creating aws stack, this might take a while... ".white
    stack = cloud_formation.stacks.create(name, template, parameters)
    sleep 1 until stack.status == "CREATE_COMPLETE"
    while ((status = stack.status) != "CREATE_COMPLETE")
        raise "error creating stack!".red if status == "ROLLBACK_COMPLETE"
    end
    puts "the CI environment has been provisioned successfully".white
    yield stack
  end

  def delete!
    stack = AWS::CloudFormation.new.stacks[name]
    (puts "couldn't find stack. Nothing to do" and return) unless stack.exists?

    stack.delete
    puts "shutdown command successful".green
  end

  private
  def name
    @data[:named]
  end

  def template
    @data[:using_template]
  end

  def parameters
    {:parameters => {"KeyName" => @data[:with_settings].aws_ssh_key_name}}
  end
end


#begin
#  settings_file = File.expand_path("#{File.dirname(__FILE__)}/../../conf/settings.yaml")
#  SETTINGS = YAML::parse(open(settings_file)).transform
#rescue
#  puts "Error loading settings. Make sure you provide a configuration file at #{settings_file}".red
#  exit
#end
#
#TEMPLATES_DIR = "#{File.dirname(__FILE__)}"
#BOOTSTRAP_FILE = "ci-bootstrap.tar.gz"
#STACK_NAME = "twitter-stream-ci"
#AWS.config(:access_key_id     => SETTINGS["aws_access_key"],
#           :secret_access_key => SETTINGS["aws_secret_access_key"])
#
#directory BUILD_DIR
#
#desc "creates the CI environment"
#task :ci_start do
#  template_body = File.read("#{TEMPLATES_DIR}/ci-cloud-formation-template.erb")
#  boot_script = ERB.new(File.read("#{TEMPLATES_DIR}/bootstrap.erb")).result(binding)
#
#  cloud_formation = AWS::CloudFormation.new
#  stack = cloud_formation.stacks[STACK_NAME]
#  unless stack.exists?
#    puts "creating aws stack, this might take a while... ".white
#    stack = cloud_formation.stacks.create(STACK_NAME,
#                                          JSON.parse(ERB.new(template_body).result(binding)),
#                                          :parameters => { "KeyName" => SETTINGS["aws_ssh_key_name"] })
#    sleep 1 until stack.status == "CREATE_COMPLETE"
#    while ((status = stack.status) != "CREATE_COMPLETE")
#      if status == "ROLLBACK_COMPLETE"
#        raise "error creating stack!".red
#      end
#    end
#    puts "the CI environment has been provisioned successfully".white
#  else
#    puts "the CI environment exists already. Nothing to do"
#  end
#  instance = stack.outputs.find { |output| output.key == "PublicIP" }
#  puts "your CI server's address is #{instance.value}"
#end
#
#desc "stops the CI environment"
#task :ci_stop do
#  stack = AWS::CloudFormation.new.stacks[STACK_NAME]
#  if stack.exists?
#    stack.delete
#    puts "shutdown command successful".green
#  else
#    puts "couldn't find stack. Nothing to do"
#  end
#end