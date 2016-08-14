# Encoding: utf-8
# Cloud Foundry Java Buildpack
# Copyright 2013-2016 the original author or authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/container'
require 'java_buildpack/container/tomcat/tomcat_utils'
require 'java_buildpack/util/tokenized_version'

module JavaBuildpack
  module Container

    # Encapsulates the detect, compile, and release functionality for the Tomcat instance.
    class TomcatInstance < JavaBuildpack::Component::VersionedDependencyComponent
      include JavaBuildpack::Container

      # Creates an instance
      #
      # @param [Hash] context a collection of utilities used the component
      def initialize(context)
        super(context) { |candidate_version| candidate_version.check_size(3) }
      end

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        download(@version, @uri) { |file| expand file }
        link_to(@application.root.children, root)
        @droplet.additional_libraries << tomcat_datasource_jar if tomcat_datasource_jar.exist?
        @droplet.additional_libraries.link_to web_inf_lib
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        true
      end

      TOMCAT_8 = JavaBuildpack::Util::TokenizedVersion.new('8.0.0').freeze

      private_constant :TOMCAT_8

      # Checks whether Tomcat instance is Tomcat 7 compatible
      def tomcat_7_compatible
        @version < TOMCAT_8
      end

      private

      DS_FILTER = /ms-sql-datasource/.freeze
      
      private_constant :DS_FILTER

      def configure_jasper
        return unless tomcat_7_compatible

        document = read_xml server_xml
        server   = REXML::XPath.match(document, '/Server').first

        listener = REXML::Element.new('Listener')
        listener.add_attribute 'className', 'org.apache.catalina.core.JasperListener'

        server.insert_before '//Service', listener

        write_xml server_xml, document
      end

#---- jayden code: begin

      def ds_supports?
        @application.services.one_service? DS_FILTER
      end
      
      def add_datasource_to_context_xml(context_xml_document)
        puts ''
        puts '>>> add_datasource_to_context_xml begin ....'
        
        if ds_supports?
          puts '>>>> Download jdbc dirver and create datasource entry in conf/context.xml...'
          # 1. download jdbc driver
          #     - jdbc download url : from env or user-defined service
          # 2. copy jdbc driver to tomcat endorsed directory
          # 3. add jdbc datasource at context.xml
          
          
          download('4.0', 'https://github.com/pivotal-choonghyun-oh/download/raw/master/sqljdbc4.jar') { |file| FileUtils.cp_r(file.path, tomcat_lib + 'sql4.jar') }
          
          resource_context = REXML::XPath.match(context_xml_document, '/Context').first
          
          credentials = @application.services.find_service(DS_FILTER)['credentials']

            resource_context.add_element  'Resource',
                                            'name' => credentials['res-name'],
                                            'auth' => credentials['auth'],
                                            'maxActive' => credentials['maxActive'],
                                            'maxIdle' => credentials['maxIdle'] ,
                                            'maxWait' => credentials['maxWait'] ,
                                            'username' => credentials['username'] ,
                                            'password' => credentials['password'] ,
                                            'driverClassName' => credentials['driverClassName'] ,
                                            'url' => credentials['url']
          
        else
          puts '>>>> NO Datasource service is attached...'
          return
        end  
      end
  
#---- jayden code: end
      
      def configure_linking
        document = read_xml context_xml
        context  = REXML::XPath.match(document, '/Context').first

        if tomcat_7_compatible
          context.add_attribute 'allowLinking', true
        else
          context.add_element 'Resources', 'allowLinking' => true
        end

        # jayden-begin
        
        add_datasource_to_context_xml document
        
        # jayden-end
        
        write_xml context_xml, document
      end

      def expand(file)
        with_timing "Expanding #{@component_name} to #{@droplet.sandbox.relative_path_from(@droplet.root)}" do
          FileUtils.mkdir_p @droplet.sandbox
          shell "tar xzf #{file.path} -C #{@droplet.sandbox} --strip 1 --exclude webapps 2>&1"

          @droplet.copy_resources
          configure_linking
          configure_jasper
        end
      end

      def root
        context_path = (@configuration['context_path'] || 'ROOT').sub(%r{^/}, '').gsub(%r{/}, '#')
        tomcat_webapps + context_path
      end

      def tomcat_datasource_jar
        tomcat_lib + 'tomcat-jdbc.jar'
      end

      def web_inf_lib
        @droplet.root + 'WEB-INF/lib'
      end

    end

  end
end
