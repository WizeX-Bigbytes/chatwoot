class Llm::BaseOpenAiService
  # DEFAULT_MODEL = 'gpt-4o-mini'.freeze  # Commented out - Using Gemini instead
  DEFAULT_GEMINI_MODEL = 'gemini-2.0-flash'.freeze
  # OPENAI_PROVIDER = 'openai'.freeze  # Commented out - Using Gemini instead
  GEMINI_PROVIDER = 'gemini'.freeze
  
  attr_reader :client, :model, :provider, :api_key

  def initialize
    @provider = ENV['CAPTAIN_LLM_PROVIDER'].presence || InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || GEMINI_PROVIDER  # Default to Gemini
    
    case @provider
    # when OPENAI_PROVIDER  # Commented out - Using Gemini instead
    #   initialize_openai
    when GEMINI_PROVIDER
      initialize_gemini
    else
      raise "Unsupported LLM provider: #{@provider}"
    end
  rescue StandardError => e
    raise "Failed to initialize LLM client: #{e.message}"
  end

  private

  # Commented out - Using Gemini instead
  # def initialize_openai
  #   access_token = ENV['CAPTAIN_OPEN_AI_API_KEY'].presence || ENV['OPENAI_API_KEY'].presence || InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_API_KEY').value
  #   @client = OpenAI::Client.new(
  #     access_token: access_token,
  #     uri_base: openai_uri_base,
  #     log_errors: Rails.env.development?
  #   )
  #   setup_openai_model
  # end

  def initialize_gemini
    @api_key = ENV['CAPTAIN_GEMINI_API_KEY'].presence || InstallationConfig.find_by!(name: 'CAPTAIN_GEMINI_API_KEY').value
    setup_gemini_model
  end

  # Commented out - Using Gemini instead
  # def openai_uri_base
  #   endpoint = ENV['CAPTAIN_OPEN_AI_ENDPOINT'].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value
  #   endpoint.presence || 'https://api.openai.com/'
  # end

  # def setup_openai_model
  #   config_value = ENV['CAPTAIN_OPEN_AI_MODEL'].presence || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value
  #   @model = (config_value.presence || DEFAULT_MODEL)
  # end

  def setup_gemini_model
    config_value = ENV['CAPTAIN_GEMINI_MODEL'].presence || InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value
    @model = (config_value.presence || DEFAULT_GEMINI_MODEL)  # Updated default
  end
end
