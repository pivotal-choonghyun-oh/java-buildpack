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

require 'java_buildpack/component/versioned_dependency_component'
require 'java_buildpack/container'
require 'java_buildpack/container/tomcat/tomcat_utils'
require 'java_buildpack/logging/logger_factory'

module JavaBuildpack
  module Container

    # Encapsulates the detect, compile, and release functionality for Tomcat Datasource support.
    class TomcatDatasource < JavaBuildpack::Component::VersionedDependencyComponent
      include JavaBuildpack::Container

      # (see JavaBuildpack::Component::BaseComponent#compile)
      def compile
        return unless supports?

        download_driver
        
        mutate_context
        
        change_http_connector_encoding
        
      end

      # (see JavaBuildpack::Component::BaseComponent#release)
      def release
      end

      protected

      # (see JavaBuildpack::Component::VersionedDependencyComponent#supports?)
      def supports?
        @application.services.one_service? DS_FILTER
      end

      private

      DS_FILTER = /tc-datasource/.freeze
      
      private_constant :DS_FILTER

      def download_driver
        puts ' '
        puts '       Adding JDBC Datasource : download jdbc driver...'
        
        credentials = @application.services.find_service(DS_FILTER)['credentials']
          
        download_url = credentials['jdbcDriverDownloadUrl']
        jdbcDriverJarFileName = credentials['jdbcDriverJarFileName']
          
        download('1.0', download_url, ) { |file| FileUtils.cp_r(file.path, tomcat_lib + jdbcDriverJarFileName) }  
        puts '      --> DONE.'
      end
      
      def mutate_context
        puts '       Adding JDBC Datasource : update conf/context.xml...'

        document = read_xml context_xml
        context  = REXML::XPath.match(document, '/Context').first

        credentials = @application.services.find_service(DS_FILTER)['credentials']
          
        context.add_element  'Resource',
                                            'name' => credentials['res-name'],
                                            'auth' => credentials['auth'],
                                            'type' => 'javax.sql.DataSource', 
                                            'maxActive' => credentials['maxActive'],
                                            'maxIdle' => credentials['maxIdle'] ,
                                            'maxWait' => credentials['maxWait'] ,
                                            'username' => credentials['username'] ,
                                            'password' => credentials['password'] ,
                                            'driverClassName' => credentials['driverClassName'] ,
                                            'url' => credentials['url']

        write_xml context_xml, document
        puts '      --> DONE.'
      end

      def change_http_connector_encoding
        puts '        Add URIEncoding to conf/server.xml...'
        server_xml_doc = read_xml server_xml
        connector_node = REXML::XPath.match(document, '/Server/Service/Connector').first
        
        connector_node.add_attribute 'URIEncoding', 'UTF-8'
        
        write_xml server_xml, server_xml_doc
        puts '      --> DONE.'
      end

    end

  end
end
