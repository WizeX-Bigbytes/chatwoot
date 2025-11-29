module Enterprise::Account::PlanUsageAndLimits
  CAPTAIN_RESPONSES = 'captain_responses'.freeze
  CAPTAIN_DOCUMENTS = 'captain_documents'.freeze
  CAPTAIN_RESPONSES_USAGE = 'captain_responses_usage'.freeze
  CAPTAIN_DOCUMENTS_USAGE = 'captain_documents_usage'.freeze

  def usage_limits
    {
      agents: ChatwootApp.max_limit,
      inboxes: ChatwootApp.max_limit,
      captain: {
        documents: { total_count: ChatwootApp.max_limit, current_available: ChatwootApp.max_limit, consumed: 0 },
        responses: { total_count: ChatwootApp.max_limit, current_available: ChatwootApp.max_limit, consumed: 0 }
      }
    }
  end

  def increment_response_usage
    current_usage = custom_attributes[CAPTAIN_RESPONSES_USAGE].to_i || 0
    custom_attributes[CAPTAIN_RESPONSES_USAGE] = current_usage + 1
    save
  end

  def reset_response_usage
    custom_attributes[CAPTAIN_RESPONSES_USAGE] = 0
    save
  end

  def update_document_usage
    # this will ensure that the document count is always accurate
    custom_attributes[CAPTAIN_DOCUMENTS_USAGE] = captain_documents.count
    save
  end

  def subscribed_features
    # Return all available features - everything is subscribed
    %w[captain sla custom_roles audit_logs help_center response_bot campaigns macros reports dashboard_apps]
  end

  def captain_monthly_limit
    default_limits = default_captain_limits

    {
      documents: self[:limits][CAPTAIN_DOCUMENTS] || default_limits['documents'],
      responses: self[:limits][CAPTAIN_RESPONSES] || default_limits['responses']
    }.with_indifferent_access
  end

  private

  def get_captain_limits(type)
    total_count = captain_monthly_limit[type.to_s].to_i

    consumed = if type == :documents
                 custom_attributes[CAPTAIN_DOCUMENTS_USAGE].to_i || 0
               else
                 custom_attributes[CAPTAIN_RESPONSES_USAGE].to_i || 0
               end

    consumed = 0 if consumed.negative?

    {
      total_count: total_count,
      current_available: (total_count - consumed).clamp(0, total_count),
      consumed: consumed
    }
  end

  def default_captain_limits
    # Always return max limits - unlimited captain usage
    { documents: ChatwootApp.max_limit, responses: ChatwootApp.max_limit }.with_indifferent_access
  end

  def plan_name
    custom_attributes['plan_name']
  end

  def agent_limits
    ChatwootApp.max_limit  # Always return unlimited agents
  end

  def get_limits(limit_name)
    ChatwootApp.max_limit  # Always return unlimited for all limits
  end

  def validate_limit_keys
    errors.add(:limits, ': Invalid data') unless self[:limits].is_a? Hash
    self[:limits] = {} if self[:limits].blank?

    limit_schema = {
      'type' => 'object',
      'properties' => {
        'inboxes' => { 'type': 'number' },
        'agents' => { 'type': 'number' },
        'captain_responses' => { 'type': 'number' },
        'captain_documents' => { 'type': 'number' }
      },
      'required' => [],
      'additionalProperties' => false
    }

    errors.add(:limits, ': Invalid data') unless JSONSchemer.schema(limit_schema).valid?(self[:limits])
  end
end
