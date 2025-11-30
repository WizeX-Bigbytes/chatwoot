# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  # Determine LLM provider (default to Gemini)
  provider = ENV['CAPTAIN_LLM_PROVIDER'].presence || 
             InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || 
             'gemini'

  if provider == 'gemini'
    # Configure for Google Gemini
    api_key = ENV['CAPTAIN_GEMINI_API_KEY'].presence || 
              InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
    model = ENV['CAPTAIN_GEMINI_MODEL'].presence || 
            InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || 
            'gemini-2.5-flash'

    if api_key.present?
      Agents.configure do |config|
        config.gemini_api_key = api_key
        config.default_model = model
        config.debug = Rails.env.development?
      end
      Rails.logger.info "[AI Agents] Configured with Gemini provider, model: #{model}"
    else
      Rails.logger.warn "[AI Agents] Gemini API key not configured"
    end
  else
    # Configure for OpenAI (fallback)
    api_key = ENV['CAPTAIN_OPEN_AI_API_KEY'].presence || 
              ENV['OPENAI_API_KEY'].presence || 
              InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    model = ENV['CAPTAIN_OPEN_AI_MODEL'].presence || 
            InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || 
            'gpt-4o-mini'
    api_endpoint = ENV['CAPTAIN_OPEN_AI_ENDPOINT'].presence || 
                   InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value

    if api_key.present?
      Agents.configure do |config|
        config.openai_api_key = api_key
        if api_endpoint.present?
          api_base = "#{api_endpoint.chomp('/')}/v1"
          config.openai_api_base = api_base
        end
        config.default_model = model
        config.debug = Rails.env.development?
      end
      Rails.logger.info "[AI Agents] Configured with OpenAI provider, model: #{model}"
    else
      Rails.logger.warn "[AI Agents] OpenAI API key not configured"
    end
  end
rescue StandardError => e
  Rails.logger.error "[AI Agents] Failed to configure AI Agents SDK: #{e.message}"
end
