require 'zlib'
require 'fileutils'
require 'yaml' # Added for metadata saving

def dump_plugin_scripts
  input_file = 'Data/PluginScripts.rxdata'
  output_dir = 'Data/PluginScripts'
  scripts = File.open(input_file, 'rb') { |f| Marshal.load(f) }
  
  folder_id = 1
  FileUtils.mkdir_p(output_dir)

  scripts.each do |id, title_hash, script_data|
    # Get plugin name from hash and sanitize
    plugin_name = (title_hash[:name] || title_hash["name"] || "Unknown").to_s.gsub(/[\x00\/\\:\*\?\"<>\|]/, '_')
    plugin_folder = File.join(output_dir, "#{folder_id}_#{plugin_name}")
    FileUtils.mkdir_p(plugin_folder)

    # 1. SAVE THE METADATA HASH
    # We save the entire Hash (including version, link, credits)
    File.write(File.join(plugin_folder, "metadata.yml"), title_hash.to_yaml)

    # 2. SAVE THE SCRIPTS
    if script_data.is_a?(Array)
      script_data.each_with_index do |sub_entry, file_id|
        sub_title, sub_content = sub_entry
        begin
          decoded = Zlib::Inflate.inflate(sub_content).delete("\r")
        rescue
          decoded = sub_content
        end
        
        # Keep original filename, but prefix with index to preserve order
        clean_sub_title = sub_title.gsub(/[\x00\/\\:\*\?\"<>\|]/, '_')
        final_filename = sprintf("%03d_%s", file_id + 1, clean_sub_title)
        final_filename += ".rb" unless final_filename.end_with?(".rb")

        File.binwrite(File.join(plugin_folder, final_filename), decoded.force_encoding("UTF-8").scrub)
      end
    end
    puts "Dumped: #{plugin_name}"
    folder_id += 1
  end
end

dump_plugin_scripts