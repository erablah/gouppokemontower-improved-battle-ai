require 'zlib'
require 'fileutils'

def extract_to_engine_plugins
  input_file = 'Data/PluginScripts.rxdata'
  output_base = 'Plugins'
  
  return puts "Data/PluginScripts.rxdata not found!" unless File.exist?(input_file)
  scripts = File.open(input_file, 'rb') { |f| Marshal.load(f) }
  FileUtils.mkdir_p(output_base)

  scripts.each_with_index do |(id, title_hash, script_data), index|
    prefix = sprintf("%03d", index + 1)
    clean_name = title_hash[:name].to_s.gsub(/[\x00\/\\:\*\?\"<>\|]/, '_')
    plugin_folder = File.join(output_base, "#{prefix}_#{clean_name}")
    FileUtils.mkdir_p(plugin_folder)

    # --- META.TXT GENERATION ---
    meta_lines = []
    
    # Basic info
    meta_lines << "Name       = #{title_hash[:name]}"
    meta_lines << "Version    = #{title_hash[:version]}" if title_hash[:version]
    
    # Essentials Version
    if title_hash[:essentials].is_a?(Array)
      title_hash[:essentials].each { |v| meta_lines << "Essentials = #{v}" }
    end

    # DEPENDENCIES (Requires, Exact, Optional)
    # Your manager stores these in :dependencies as [type, name, version] or [name, version]
    if title_hash[:dependencies].is_a?(Array)
      title_hash[:dependencies].each do |dep|
        if dep.is_a?(Array)
          case dep[0]
          when :exact
            meta_lines << "Exact      = #{dep[1]}, #{dep[2]}"
          when :optional
            meta_lines << "Optional   = #{dep[1]}, #{dep[2]}"
          else
            # Check for [name, version, type] or [name, version]
            if dep.length == 3
              meta_lines << "Requires   = #{dep[0]}, #{dep[1]}, #{dep[2]}"
            elsif dep.length == 2
              meta_lines << "Requires   = #{dep[0]}, #{dep[1]}"
            end
          end
        else
          # Single string dependency
          meta_lines << "Requires   = #{dep}"
        end
      end
    end

    # CONFLICTS
    if title_hash[:incompatibilities].is_a?(Array)
      title_hash[:incompatibilities].each do |inc|
        if inc.is_a?(Array)
          meta_lines << "Conflicts  = #{inc[0]}, #{inc[1]}"
        else
          meta_lines << "Conflicts  = #{inc}"
        end
      end
    end

    # CREDITS & WEBSITE
    if title_hash[:credits].is_a?(Array)
      meta_lines << "Credits    = #{title_hash[:credits].join(', ')}"
    end
    meta_lines << "Website    = #{title_hash[:link]}" if title_hash[:link]

    # CATCH-ALL for other fields (Scripts, etc.)
    title_hash.each do |key, value|
      next if [:name, :version, :essentials, :dependencies, :incompatibilities, :credits, :link].include?(key)
      label = key.to_s.upcase
      if value.is_a?(Array)
        value.each { |v| meta_lines << "#{label.ljust(10)} = #{v}" }
      else
        meta_lines << "#{label.ljust(10)} = #{value}"
      end
    end

    File.write(File.join(plugin_folder, "meta.txt"), meta_lines.join("\n"))

    # --- SCRIPT EXTRACTION ---
    if script_data.is_a?(Array)
      script_data.each_with_index do |(sub_title, sub_content), f_idx|
        begin
          decoded = Zlib::Inflate.inflate(sub_content).delete("\r")
          decoded.force_encoding("UTF-8").scrub!
        rescue
          decoded = sub_content
        end
        file_prefix = sprintf("%03d", f_idx + 1)
        sub_filename = sub_title.gsub(/[\x00\/\\:\*\?\"<>\|]/, '_')
        sub_filename += ".rb" unless sub_filename.downcase.end_with?(".rb")
        File.binwrite(File.join(plugin_folder, "#{file_prefix}_#{sub_filename}"), decoded)
      end
    end
    puts "Extracted: [#{prefix}] #{clean_name}"
  end
end

extract_to_engine_plugins