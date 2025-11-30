# require 'openai'  # Commented out - Using Gemini instead
require 'net/http'
require 'json'

class Captain::LlmService
  include Integrations::LlmInstrumentation
  # OPENAI_PROVIDER = 'openai'.freeze  # Commented out - Using Gemini instead
  GEMINI_PROVIDER = 'gemini'.freeze

  def initialize(config)
    @provider = config[:provider] || GEMINI_PROVIDER  # Default to Gemini
    @api_key = config[:api_key]
    @model = config[:model]
    @logger = Rails.logger

    case @provider
    # when OPENAI_PROVIDER  # Commented out - Using Gemini instead
    #   @client = OpenAI::Client.new(
    #     access_token: @api_key,
    #     log_errors: Rails.env.development?
    #   )
    #   @model ||= 'gpt-4o'
    when GEMINI_PROVIDER
      @model ||= 'gemini-2.0-flash'  # Updated to match Google AI Studio
    end
  end

  def call(messages, functions = [])
    case @provider
    when GEMINI_PROVIDER
      # Instrument Gemini call for observability
      instrument_llm_call(instrumentation_params(messages)) do
        call_gemini(messages, functions)
      end
    else
      handle_error(StandardError.new("Unsupported provider: #{@provider}"))
    end
  rescue StandardError => e
    handle_error(e)
  end

  private

  # Commented out - Using Gemini instead
  # def call_openai(messages, functions)
  #   openai_params = {
  #     model: @model,
  #     response_format: { type: 'json_object' },
  #     messages: messages
  #   }
  #   openai_params[:tools] = functions if functions.any?
  #
  #   response = @client.chat(parameters: openai_params)
  #   handle_openai_response(response)
  # end
  def call_gemini(messages, functions)
    # Using Google AI Studio API format: https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent
    uri = URI("https://generativelanguage.googleapis.com/v1beta/models/#{@model}:generateContent")
    
    gemini_messages = convert_messages_to_gemini(messages)
    
    request_body = {
      contents: gemini_messages,
      generationConfig: {
        temperature: 0.7,
        topK: 40,
        topP: 0.95,
        maxOutputTokens: 8192,
        responseMimeType: 'application/json'
      }
    }

    # Add function declarations if functions are provided
    if functions.any?
      request_body[:tools] = [{
        functionDeclarations: convert_functions_to_gemini(functions)
      }]
    end

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request['X-goog-api-key'] = @api_key  # Updated to use X-goog-api-key header per Google AI Studio
    request.body = request_body.to_json

    @logger.info("Gemini API request to #{uri}: #{request.body}")
    response = http.request(request)
    @logger.info("Gemini API response (#{response.code}): #{response.body}")

    handle_gemini_response(JSON.parse(response.body))
  end

  def instrumentation_params(messages)
    {
      span_name: 'llm.captain',
      account_id: nil, # Can be populated by caller if needed
      conversation_id: nil,
      feature_name: 'captain',
      model: @model,
      messages: messages.map { |m| { 'role' => m[:role], 'content' => m[:content] } },
      temperature: 0.7,
      provider: 'gemini'
    }
  end

  def convert_messages_to_gemini(messages)
    gemini_contents = []
    
    messages.each do |msg|
      role = msg[:role] == 'assistant' ? 'model' : 'user'
      # Skip system messages or combine them into user messages
      next if msg[:role] == 'system' && gemini_contents.empty?
      
      if msg[:role] == 'system'
        # Prepend system message to next user message
        content = "System: #{msg[:content]}"
      else
        content = msg[:content]
      end

      gemini_contents << {
        role: role,
        parts: [{ text: content }]
      }
    end

    gemini_contents
  end

  def convert_functions_to_gemini(functions)
    functions.map do |func|
      {
        name: func[:function][:name],
        description: func[:function][:description],
        parameters: func[:function][:parameters]
      }
    end
  end

  def handle_gemini_response(response)
    return handle_error(StandardError.new("Gemini API error: #{response}")) if response['error']

    candidate = response.dig('candidates', 0)
    return handle_error(StandardError.new('No candidates in response')) unless candidate

    content = candidate.dig('content', 'parts', 0)
    
    # Check for function calls
    if content['functionCall']
      handle_gemini_function_call(content['functionCall'])
    elsif content['text']
      handle_direct_response(content['text'])
    else
      handle_error(StandardError.new('Unexpected response format'))
    end
  end

  def handle_gemini_function_call(function_call)
    # Convert Gemini function call to OpenAI format for compatibility
    tool_call = {
      'function' => {
        'name' => function_call['name'],
        'arguments' => function_call['args'].to_json
      }
    }
    handle_tool_calls(tool_call)
  end

  def handle_tool_calls(tool_call)
    {
      tool_call: tool_call,
      output: nil,
      stop: false
    }
  end

  def handle_direct_response(content)
    content = content.strip
    parsed = JSON.parse(content)

    {
      output: parsed['result'] || parsed['thought_process'],
      stop: parsed['stop'] || false
    }
  rescue JSON::ParserError => e
    handle_error(e, content)
  end

  def handle_error(error, content = nil)
    @logger.error("LLM call failed: #{error.message}")
    @logger.error(error.backtrace.join("\n")) if error.backtrace
    @logger.error("Content: #{content}") if content

    { output: 'Error occurred, retrying', stop: false }
  end
end
