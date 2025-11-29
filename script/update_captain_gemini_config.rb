# frozen_string_literal: true

# Rails runner script to update Captain configuration with Gemini support
# Usage: bundle exec rails runner scripts/update_captain_gemini_config.rb

puts '=' * 60
puts 'Updating Captain Configuration with Gemini Support'
puts '=' * 60
puts ''

begin
  puts 'Loading installation configuration from YAML...'
  
  # Force reload configuration with new values
  ConfigLoader.new.process(reconcile_only_new: false)
  
  puts '✓ Configuration loaded successfully!'
  puts ''
  
  # Verify new configs were created
  gemini_configs = [
    'CAPTAIN_LLM_PROVIDER',
    'CAPTAIN_GEMINI_API_KEY',
    'CAPTAIN_GEMINI_MODEL'
  ]
  
  puts 'Verifying new configuration options...'
  gemini_configs.each do |config_name|
    config = InstallationConfig.find_by(name: config_name)
    if config
      puts "  ✓ #{config_name} - Created"
    else
      puts "  ✗ #{config_name} - Missing (this might be expected for optional configs)"
    end
  end
  
  puts ''
  puts '=' * 60
  puts '✓ Configuration Update Complete!'
  puts '=' * 60
  puts ''
  puts 'New Captain Configuration Options Available:'
  puts ''
  puts '1. CAPTAIN_LLM_PROVIDER'
  puts '   - Type: Select (openai or gemini)'
  puts '   - Default: openai'
  puts '   - Description: Choose your LLM provider'
  puts ''
  puts '2. CAPTAIN_GEMINI_API_KEY'
  puts '   - Type: Secret'
  puts '   - Description: Your Google Gemini API key'
  puts '   - Get yours at: https://makersuite.google.com/app/apikey'
  puts ''
  puts '3. CAPTAIN_GEMINI_MODEL'
  puts '   - Type: Text'
  puts '   - Default: gemini-1.5-pro'
  puts '   - Options: gemini-1.5-pro, gemini-1.5-flash, gemini-2.0-flash-exp'
  puts ''
  puts '=' * 60
  puts 'Next Steps:'
  puts '=' * 60
  puts '1. Go to Super Admin → Installation Config in Chatwoot'
  puts '2. Scroll to the Captain section'
  puts '3. Set CAPTAIN_LLM_PROVIDER to "gemini"'
  puts '4. Enter your CAPTAIN_GEMINI_API_KEY'
  puts '5. (Optional) Change CAPTAIN_GEMINI_MODEL if needed'
  puts '6. Save changes'
  puts '7. Restart Chatwoot services'
  puts ''
  puts 'For detailed instructions, see: CAPTAIN_GEMINI_SETUP.md'
  puts ''
  
rescue StandardError => e
  puts ''
  puts '✗ Error updating configuration:'
  puts e.message
  puts e.backtrace.first(5).join("\n")
  puts ''
  puts 'Please ensure you are running this from the Chatwoot directory'
  exit 1
end
