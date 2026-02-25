require 'zlib'
require 'fileutils'
require 'yaml'

def compile_plugin_scripts
  input_dir = 'Data/PluginScripts'
  output_file = 'Data/PluginScripts.rxdata'
  final_scripts = []
  
  # Sort folders by their numeric prefix
  plugin_folders = Dir.glob(File.join(input_dir, "*/")).sort_by { |f| File.basename(f).to_i }

  plugin_folders.each do |folder_path|
    metadata_path = File.join(folder_path, "metadata.yml")
    
    # LOAD THE METADATA
    if File.exist?(metadata_path)
      title_hash = YAML.safe_load(File.read(metadata_path), permitted_classes: [Symbol])
    else
      # Fallback if file is missing
      title_hash = { name: File.basename(folder_path).sub(/^\d+_/, ""), essentials: ["21.1"] }
    end

    # COLLECT SCRIPTS
    script_entries = []
    rb_files = Dir.glob(File.join(folder_path, "*.rb")).sort_by { |f| File.basename(f).to_i }

    rb_files.each do |file_path|
      # Strip the '001_' prefix for the internal title
      internal_title = File.basename(file_path).sub(/^\d+_/, "")
      content = File.binread(file_path).gsub("\r", "")
      compressed = Zlib::Deflate.deflate(content)
      script_entries << [internal_title, compressed]
    end

    # ID doesn't matter much for Plugins, so we use a consistent hash of the name
    id = title_hash[:name].hash.abs
    final_scripts << [id, title_hash, script_entries]
    puts "Compiled: #{title_hash[:name]}"
  end

  File.open(output_file, 'wb') { |f| Marshal.dump(final_scripts, f) }
  puts "\nFinished! Data/PluginScripts.rxdata is ready."
end

compile_plugin_scripts