require 'aws_settings'
require 'cloud_formation_template'
require 'stacks'

namespace :aws do
  SETTINGS = AWSSettings.prepare
  STACK_NAME = "twitter-stream-ci"
  SCRIPTS_DIR = "#{File.dirname(__FILE__)}/../../scripts"

  desc "creates the CI environment"
  task :ci_start => ["clean", "package:puppet"] do
    buildserver_boot_script = erb(File.read("#{SCRIPTS_DIR}/boot.erb"),
                                  :role => "buildserver",
                                  :boot_package_url => setup_bootstrap)
    template = CloudFormationTemplate.new("ci-cloud-formation-template",
                                          :boot_script => buildserver_boot_script)
    Stacks.new(:named => STACK_NAME,
               :using_template => template.as_json_obj,
               :with_settings => SETTINGS).create do |stack|

      instance = stack.outputs.find { |output| output.key == "PublicIP" }
      puts "your CI server's address is #{instance.value}"
    end
  end

  desc "stops the CI environment"
  task :ci_stop do
    Stacks.new(:named => STACK_NAME).delete!
  end

  task :build_appserver do
    template = CloudFormationTemplate.new("appserver-creation", {})
    stack = Stacks.new(:named => "appserver-creation",
                       :using_template => template.as_json_obj,
                       :with_settings => SETTINGS)
    begin
      stack.create do |stack|
        ec2 = AWS::EC2.new
        instance = stack.resources.find { |resource| resource.resource_type == "AWS::EC2::Instance" }
        test_application instance.public_dns_name

        image = ec2.images.create(:instance_id => instance.physical_resource_id, :name => "testimage")
        sleep 1 until image.state.to_s.eql? "available"
        File.open("#{BUILD_DIR}/image", "w") { |file| file.write(image.id) }
      end
    ensure
      stack.delete!
    end
  end

  def test_application(host)
    puts "testing..."
    (1..10).each do |n|
      puts n
      sleep 1
    end
    puts "all good!"
  end

  def setup_bootstrap
    s3 = AWS::S3.new
    bucket_name = "#{STACK_NAME}-bootstrap-bucket"
    bucket = s3.buckets[bucket_name]
    unless bucket.exists?
      puts "creating S3 bucket".cyan
      bucket = s3.buckets.create(bucket_name)
    end
    puts "uploading bootstrap package...".cyan
    bucket.objects[BOOTSTRAP_FILE].write(File.read("#{BUILD_DIR}/#{BOOTSTRAP_FILE}"))
    bucket.objects[BOOTSTRAP_FILE].url_for(:read)
  end

  desc "creates the UAT environment"
  task :uat_start do
    template = CloudFormationTemplate.new(:from => "vpc-uat-formation-template", :with_vars => ["boot_script"])

    Stacks.new(:named => "uat-test",
               :using_template => template.as_json_obj,
               :with_settings => AWSSettings.prepare).create do |stack|
      p stack.outputs
    end
  end

  desc "destroys the UAT environment"
  task :uat_stop do
    AWSSettings.prepare
    Stacks.new(:named => "uat-test").delete!
  end
end
