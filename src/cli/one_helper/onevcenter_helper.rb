
# -------------------------------------------------------------------------- #
# Copyright 2002-2018, OpenNebula Project, OpenNebula Systems                #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

require 'one_helper'

class OneVcenterHelper < OpenNebulaHelper::OneHelper

    TABLE = {
        "datastores" => {
            :struct  => ["DATASTORE_LIST", "DATASTORE"],
            :columns => [:IMID, :REF, :VCENTER, :NAME, :CLUSTERS]
        },
        "networks" => {
            :struct  => ["NETWORK_LIST", "NETWORK"],
            :columns => [:IMID, :REF, :VCENTER, :NAME, :CLUSTERS]
        },
        "templates" => {
            :struct  => ["NETWORK_LIST", "NETWORK"],
            :columns => [:IMID, :REF, :VCENTER, :NAME]
        }
    }

    def connection_options(object_name, options)
        if  options[:vuser].nil? || options[:vcenter].nil?
            raise "vCenter connection parameters are mandatory to import"\
                  " #{object_name}:\n"\
                  "\t --vcenter vCenter hostname\n"\
                  "\t --vuser username to login in vcenter"
        end

        password = options[:vpass] || OpenNebulaHelper::OneHelper.get_password
        {
           :user     => options[:vuser],
           :password => password,
           :host     => options[:vcenter]
        }
    end

    def cli_format(o, hash)
        {TABLE[o][:struct].first => {TABLE[o][:struct].last => hash.values}}
    end

    def list_object(options, list)
        list = cli_format(options[:object], list)
        table = format_list(options[:object])
        table.show(list)
    end

    def template_dialogue(t)
    begin
        # default opts
        opts = {
            linked_clone: '',
            copy: '',
            name: '',
            folder: '',
            resourcepool: [],
            type: ''
        }

        # LINKED CLONE OPTION
        STDOUT.print "\n    For faster deployment operations"\
                     " and lower disk usage, OpenNebula"\
                     " can create new VMs as linked clones."\
                     "\n    Would you like to use Linked Clones with VMs based on this template (y/[n])? "

        if STDIN.gets.strip.downcase == 'y'
            opts[:linked_clone] = '1'


            # CREATE COPY OPTION
            STDOUT.print "\n    Linked clones requires that delta"\
                         " disks must be created for each disk in the template."\
                         " This operation may change the template contents."\
                         " \n    Do you want OpenNebula to create a copy of the template,"\
                         " so the original template remains untouched ([y]/n)? "

            if STDIN.gets.strip.downcase != 'n'
                opts[:copy] = '1'

                # NAME OPTION
                STDOUT.print "\n    The new template will be named"\
                             " adding a one- prefix to the name"\
                             " of the original template. \n"\
                             "    If you prefer a different name"\
                             " please specify or press Enter"\
                             " to use defaults: "

                template_name = STDIN.gets.strip.downcase
                opts[:name] = template_name

                STDOUT.print "\n    WARNING!!! The cloning operation can take some time"\
                             " depending on the size of disks.\n"
            else
                opts[:copy] = '0'
            end
        else
            opts[:linked_clone] = '0'
        end

        STDOUT.print "\n\n    Do you want to specify a folder where"\
                        " the deployed VMs based on this template will appear"\
                        " in vSphere's VM and Templates section?"\
                        "\n    If no path is set, VMs will be placed in the same"\
                        " location where the template lives."\
                        "\n    Please specify a path using slashes to separate folders"\
                        " e.g /Management/VMs or press Enter to use defaults: "\

        vcenter_vm_folder = STDIN.gets.strip
        opts[:folder] = vcenter_vm_folder

        ## Add existing disks to template (OPENNEBULA_MANAGED)
        STDOUT.print "\n    The existing disks and networks in the template"\
                     " are being imported, \e[96mplease be patient...\e[39m\n"

        # Resource Pools OPTION
        rp_input = ""
        rp_split = t[:rp].split("|")
        if rp_split.size > 3
            STDOUT.print "\n\n    This template is currently set to "\
                "launch VMs in the default resource pool."\
                "\n    Press y to keep this behaviour, n to select"\
                " a new resource pool or d to delegate the choice"\
                " to the user ([y]/n/d)? "

            answer =  STDIN.gets.strip.downcase

            case answer
            when 'd'
                list_of_rp   = rp_split[-2]
                default_rp   = rp_split[-1]
                rp_input     = rp_split[0] + "|" + rp_split[1] + "|" +
                                rp_split[2] + "|"

                # Available list of resource pools
                input_str = "    The list of available resource pools "\
                            "to be presented to the user are "\
                            "\"#{list_of_rp}\""
                input_str+= "\n    Press y to agree, or input a comma"\
                            " separated list of resource pools to edit "\
                            "([y]/comma separated list) "
                STDOUT.print input_str

                answer = STDIN.gets.strip

                if !answer.empty? && answer.downcase != 'y'
                    rp_input += answer + "|"
                else
                    rp_input += rp_split[3] + "|"
                end

                # Default
                input_str   = "    The default resource pool presented "\
                                "to the end user is set to"\
                                " \"#{default_rp}\"."
                input_str+= "\n    Press y to agree, or input a new "\
                            "resource pool ([y]/resource pool name) "
                STDOUT.print input_str

                answer = STDIN.gets.strip

                if !answer.empty? && answer.downcase != 'y'
                    rp_input += answer
                else
                    rp_input += rp_split[4]
                end
            when 'n'

                list_of_rp   = rp_split[-2]

                STDOUT.print "    The list of available resource pools is:\n\n"

                index = 1
                t[:rp_list].each do |r|
                    list_str = "    - #{r[:name]}\n"
                    index += 1
                    STDOUT.print list_str
                end

                input_str = "\n    Please input the new default"\
                            " resource pool name: "

                STDOUT.print input_str

                answer = STDIN.gets.strip

                t[:one] << "VCENTER_RESOURCE_POOL=\"#{answer}\"\n"
            end
        end

        if !rp_input.empty?
            t[:one] << "USER_INPUTS=["
            t[:one] << "VCENTER_RESOURCE_POOL=\"#{rp_input}\"," if !rp_input.empty?
            t[:one] = t[:one][0..-2]
            t[:one] << "]"
        end

    rescue Interrupt => e
        puts "\n"
        exit 0 #Ctrl+C
    rescue Exception => e
        puts "whats happenning my brotha"
    end

    end


    def format_list(type)
        table = CLIHelper::ShowTable.new() do
            column :IMID, "identifier for ...", :size=>4 do |d|
                d[:import_id]
            end

            column :REF, "ref", :left, :size=>15 do |d|
                d[:ref]
            end

            column :VCENTER, "vCenter", :left, :size=>20 do |d|
                d[:vcenter]
            end

            column :NAME, "Name", :left, :size=>20 do |d|
                d[:name] || d[:simple_name]
            end

            column :CLUSTERS, "CLUSTERS", :left, :size=>10 do |d|
                d[:cluster].to_s
            end

            default(*TABLE[type][:columns])
        end

        table
    end
end
