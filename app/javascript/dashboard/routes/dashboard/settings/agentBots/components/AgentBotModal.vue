<script setup>
import { ref, computed, reactive, watch } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { required, helpers, url } from '@vuelidate/validators';
import { useVuelidate } from '@vuelidate/core';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import { useToggle } from '@vueuse/core';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import AccessToken from 'dashboard/routes/dashboard/settings/profile/AccessToken.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'create',
    validator: value => ['create', 'edit'].includes(value),
  },
  selectedBot: {
    type: Object,
    default: () => ({}),
  },
});

const MODAL_TYPES = {
  CREATE: 'create',
  EDIT: 'edit',
};

const store = useStore();
const { t } = useI18n();
const dialogRef = ref(null);
const uiFlags = useMapGetter('agentBots/getUIFlags');

const formState = reactive({
  botName: '',
  botDescription: '',
  botUrl: '',
  botAvatar: null,
  botAvatarUrl: '',
  typebotId: '', // Add Typebot ID field
});

const [showAccessToken, toggleAccessToken] = useToggle();
const accessToken = ref('');
const createdBotId = ref(null); // Store bot ID after creation
const isSavingConfig = ref(false); // Loading state for config save

const v$ = useVuelidate(
  {
    botName: {
      required: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.NAME'),
        required
      ),
    },
    botUrl: {
      required: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.URL'),
        required
      ),
      url: helpers.withMessage(
        () => t('AGENT_BOTS.FORM.ERRORS.VALID_URL'),
        url
      ),
    },
    typebotId: {
      // Required only when saving configuration after bot creation
      required: helpers.withMessage(
        () => 'Typebot ID is required',
        (value) => {
          // Only validate if we're in the access token screen
          if (showAccessToken.value) {
            return !!value && value.trim().length > 0;
          }
          return true;
        }
      ),
    },
  },
  formState
);

const isLoading = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? uiFlags.value.isCreating
    : uiFlags.value.isUpdating
);

const dialogTitle = computed(() => {
  if (showAccessToken.value) {
    return props.type === MODAL_TYPES.CREATE
      ? 'Configure Bot - Typebot Integration'
      : t('AGENT_BOTS.ACCESS_TOKEN.TITLE');
  }

  return props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.ADD.TITLE')
    : t('AGENT_BOTS.EDIT.TITLE');
});

const dialogDescription = computed(() => {
  if (showAccessToken.value) {
    return props.type === MODAL_TYPES.CREATE
      ? 'Enter your Typebot ID to complete the bot configuration. This will link your Chatwoot bot to your Typebot flow.'
      : t('AGENT_BOTS.ACCESS_TOKEN.DESCRIPTION');
  }
  return '';
});

const confirmButtonLabel = computed(() =>
  props.type === MODAL_TYPES.CREATE
    ? t('AGENT_BOTS.FORM.CREATE')
    : t('AGENT_BOTS.FORM.UPDATE')
);

const botNameError = computed(() =>
  v$.value.botName.$error ? v$.value.botName.$errors[0]?.$message : ''
);

const botUrlError = computed(() =>
  v$.value.botUrl.$error ? v$.value.botUrl.$errors[0]?.$message : ''
);

const showAccessTokenInput = computed(
  () =>
    showAccessToken.value ||
    props.type === MODAL_TYPES.EDIT ||
    accessToken.value
);

const resetForm = () => {
  Object.assign(formState, {
    botName: '',
    botDescription: '',
    botUrl: '',
    botAvatar: null,
    botAvatarUrl: '',
    typebotId: '',
  });
  v$.value.$reset();
  createdBotId.value = null;
};

const handleImageUpload = ({ file, url: avatarUrl }) => {
  formState.botAvatar = file;
  formState.botAvatarUrl = avatarUrl;
};

const handleAvatarDelete = async () => {
  if (props.selectedBot?.id) {
    try {
      await store.dispatch(
        'agentBots/deleteAgentBotAvatar',
        props.selectedBot.id
      );
      formState.botAvatar = null;
      formState.botAvatarUrl = '';
      useAlert(t('AGENT_BOTS.AVATAR.SUCCESS_DELETE'));
    } catch (error) {
      useAlert(t('AGENT_BOTS.AVATAR.ERROR_DELETE'));
    }
  } else {
    formState.botAvatar = null;
    formState.botAvatarUrl = '';
  }
};

const handleSubmit = async () => {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  // If showing access token, save the configuration
  if (showAccessToken.value) {
    await saveBotConfiguration();
    return;
  }

  const botData = {
    name: formState.botName,
    description: formState.botDescription,
    outgoing_url: formState.botUrl,
    bot_type: 'webhook',
    avatar: formState.botAvatar,
  };

  const isCreate = props.type === MODAL_TYPES.CREATE;

  try {
    const actionPayload = isCreate
      ? botData
      : { id: props.selectedBot.id, data: botData };

    const response = await store.dispatch(
      `agentBots/${isCreate ? 'create' : 'update'}`,
      actionPayload
    );

    const alertKey = isCreate
      ? t('AGENT_BOTS.ADD.API.SUCCESS_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.SUCCESS_MESSAGE');
    useAlert(alertKey);

    // Show access token after creation
    if (isCreate) {
      const { access_token: responseAccessToken, id } = response || {};

      if (id && responseAccessToken) {
        accessToken.value = responseAccessToken;
        createdBotId.value = id;
        
        // Auto-update webhook URL with bot ID
        // If user entered URL without bot ID, append it
        const webhookBaseUrl = formState.botUrl.replace(/\/$/, ''); // Remove trailing slash
        const hasPlaceholder = webhookBaseUrl.includes('{botId}');
        const hasBotIdParam = /\/\d+$/.test(webhookBaseUrl); // Check if already has numeric ID at end
        
        if (hasPlaceholder) {
          // Replace {botId} placeholder with actual bot ID
          const updatedUrl = webhookBaseUrl.replace('{botId}', id);
          await updateBotWebhookUrl(id, updatedUrl);
          formState.botUrl = updatedUrl;
        } else if (!hasBotIdParam) {
          // Append bot ID to URL if not already there
          const updatedUrl = `${webhookBaseUrl}/${id}`;
          await updateBotWebhookUrl(id, updatedUrl);
          formState.botUrl = updatedUrl;
        }
        
        toggleAccessToken(true);
      } else {
        accessToken.value = '';
        dialogRef.value.close();
        resetForm();
      }
    } else {
      dialogRef.value.close();
      resetForm();
    }
  } catch (error) {
    const errorKey = isCreate
      ? t('AGENT_BOTS.ADD.API.ERROR_MESSAGE')
      : t('AGENT_BOTS.EDIT.API.ERROR_MESSAGE');
    useAlert(errorKey);
  }
};

/**
 * Update bot webhook URL with actual bot ID
 */
const updateBotWebhookUrl = async (botId, newUrl) => {
  try {
    await store.dispatch('agentBots/update', {
      id: botId,
      data: {
        name: formState.botName,
        description: formState.botDescription,
        outgoing_url: newUrl,
        bot_type: 'webhook',
      },
    });
    console.log(`✅ Updated webhook URL and test to: ${newUrl}`);
  } catch (error) {
    console.error('Failed to update webhook URL:', error);
    // Don't show error to user as bot is already created
  }
};

/**
 * Save bot configuration to backend (Typebot ID + Access Token mapping)
 */
const saveBotConfiguration = async () => {
  console.log('[AgentBotModal] saveBotConfiguration called - BUTTON CLICKED!');
  console.log('[AgentBotModal] props.selectedBot:', props.selectedBot);
  console.log('[AgentBotModal] createdBotId.value:', createdBotId.value);
  console.log('[AgentBotModal] type:', props.type);
  
  if (!formState.typebotId || !formState.typebotId.trim()) {
    console.warn('[AgentBotModal] Validation failed: typebotId empty');
    useAlert('Please enter a Typebot ID');
    return;
  }

  // Determine bot id: prefer createdBotId (creation flow), fallback to selectedBot.id (edit flow)
  const botIdToSave = createdBotId.value || (props.selectedBot && props.selectedBot.id);
  if (!botIdToSave) {
    console.warn('[AgentBotModal] Validation failed: missing bot ID', {
      createdBotId: createdBotId.value,
      selectedBot: props.selectedBot,
      hasSelectedBot: !!props.selectedBot,
      selectedBotId: props.selectedBot?.id
    });
    useAlert('Missing bot ID');
    return;
  }

  console.log('[AgentBotModal] Validation passed, setting isSavingConfig=true');
  isSavingConfig.value = true;

  try {
    // DEBUG: log start
    console.debug('[AgentBotModal] saveBotConfiguration start', {
      botIdToSave,
      typebotId: formState.typebotId,
    });
    // show a quick UI hint that saving started
    useAlert('Saving bot configuration...', 'info');
    // Call backend API to save the typebot_id to Chatwoot's agent_bots table
    const backendUrl = window.location.hostname === 'localhost' || window.location.hostname.includes('localhost')
      ? 'http://localhost:5000'
      : 'https://wizex.tech';
    
    const payload = {
      chatwoot_bot_id: botIdToSave,
      typebot_id: formState.typebotId.trim(),
    };

    console.debug('[AgentBotModal] POST payload', payload);

    const response = await fetch(`${backendUrl}/api/webhooks/bot-config`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    let result = null;
    try {
      result = await response.json();
    } catch (e) {
      console.error('[AgentBotModal] Failed to parse JSON response', e);
    }

    console.debug('[AgentBotModal] response', { status: response.status, ok: response.ok, result });

    if (response.ok && result && result.success) {
      useAlert('Bot configuration saved successfully! You can now assign this bot to an inbox.');
      resetForm();
      dialogRef.value.close();
    } else {
      const errMsg = (result && (result.error || result.message)) || `Failed to save bot configuration (status ${response.status})`;
      console.error('[AgentBotModal] save failed', { status: response.status, result });
      useAlert(errMsg);
    }
  } catch (error) {
    console.error('[AgentBotModal] Error saving bot configuration:', error);
    useAlert(`Failed to save bot configuration. ${error.message || ''}`);
  } finally {
    isSavingConfig.value = false;
  }
};

const initializeForm = () => {
  if (props.selectedBot && Object.keys(props.selectedBot).length) {
    console.log('[AgentBotModal] Initializing form with selectedBot:', props.selectedBot);
    const {
      name,
      description,
      outgoing_url: botUrl,
      thumbnail,
      bot_config: botConfig,
      access_token: botAccessToken,
    } = props.selectedBot;
    formState.botName = name || '';
    formState.botDescription = description || '';
    formState.botUrl = botUrl || botConfig?.webhook_url || '';
    formState.botAvatarUrl = thumbnail || '';

    // Prefill Typebot ID when editing
    formState.typebotId = props.selectedBot?.typebot_id || botConfig?.typebot_id || '';
    console.log('[AgentBotModal] Set typebotId to:', formState.typebotId);

    if (botAccessToken && props.type === MODAL_TYPES.EDIT) {
      accessToken.value = botAccessToken;
    }
  } else {
    resetForm();
  }
};

const onCopyToken = async value => {
  await copyTextToClipboard(value);
  useAlert(t('AGENT_BOTS.ACCESS_TOKEN.COPY_SUCCESSFUL'));
};

const onResetToken = async () => {
  const response = await store.dispatch(
    'agentBots/resetAccessToken',
    props.selectedBot.id
  );
  if (response) {
    accessToken.value = response.access_token;
    useAlert(t('AGENT_BOTS.ACCESS_TOKEN.RESET_SUCCESS'));
  } else {
    useAlert(t('AGENT_BOTS.ACCESS_TOKEN.RESET_ERROR'));
  }
};

const closeModal = () => {
  if (!showAccessToken.value) v$.value?.$reset();
  accessToken.value = '';
  toggleAccessToken(false);
};

const onClickClose = () => {
  closeModal();
  dialogRef.value.close();
};

watch(() => props.selectedBot, initializeForm, { immediate: true, deep: true });

defineExpose({ dialogRef });
</script>

<template>
  <Dialog
    ref="dialogRef"
    type="edit"
    :title="dialogTitle"
    :description="dialogDescription"
    :show-cancel-button="false"
    :show-confirm-button="false"
    @close="closeModal"
  >
    <form class="flex flex-col gap-4" @submit.prevent="handleSubmit">
      <div
        v-if="!showAccessToken || type === MODAL_TYPES.EDIT"
        class="flex flex-col gap-4"
      >
        <div class="mb-2 flex flex-col items-start">
          <span class="mb-2 text-sm font-medium text-n-slate-12">
            {{ $t('AGENT_BOTS.FORM.AVATAR.LABEL') }}
          </span>
          <Avatar
            :src="formState.botAvatarUrl"
            :name="formState.botName"
            :size="68"
            allow-upload
            icon-name="i-lucide-bot-message-square"
            @upload="handleImageUpload"
            @delete="handleAvatarDelete"
          />
        </div>

        <Input
          id="bot-name"
          v-model="formState.botName"
          :label="$t('AGENT_BOTS.FORM.NAME.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.NAME.PLACEHOLDER')"
          :message="botNameError"
          :message-type="botNameError ? 'error' : 'info'"
          @blur="v$.botName.$touch()"
        />

        <TextArea
          id="bot-description"
          v-model="formState.botDescription"
          :label="$t('AGENT_BOTS.FORM.DESCRIPTION.LABEL')"
          :placeholder="$t('AGENT_BOTS.FORM.DESCRIPTION.PLACEHOLDER')"
        />

        <Input
          id="bot-url"
          v-model="formState.botUrl"
          :label="$t('AGENT_BOTS.FORM.WEBHOOK_URL.LABEL')"
          :placeholder="'https://wizex.tech/api/webhooks/chatwoot (bot ID will be added automatically)'"
          :message="botUrlError || 'The bot ID will be appended automatically after creation'"
          :message-type="botUrlError ? 'error' : 'info'"
          @blur="v$.botUrl.$touch()"
        />
      </div>

      <!-- Typebot ID Field - shown in edit mode or after bot creation -->
      <div v-if="showAccessTokenInput" class="mb-4">
        <Input
          id="typebot-id"
          v-model="formState.typebotId"
          label="Typebot ID"
          placeholder="e.g., lead-generation-x1xxa2r"
          message="Copy this from your Typebot publish page"
          message-type="info"
          @blur="v$.typebotId.$touch()"
        />
        <!-- Info box only shown after bot creation in create flow -->
        <div v-if="showAccessToken && type === MODAL_TYPES.CREATE && createdBotId" class="mt-3 p-3 bg-n-slate-2 rounded-md">
          <p class="text-sm text-n-slate-11 mb-2">
            <strong>📋 Setup Complete:</strong>
          </p>
          <p class="text-xs text-n-slate-11 mb-1">
            ✅ Bot Created (ID: <code class="px-1 py-0.5 bg-n-slate-3 rounded">{{ createdBotId }}</code>)
          </p>
          <p class="text-xs text-n-slate-11 mb-1">
            ✅ Webhook URL: <code class="px-1 py-0.5 bg-n-slate-3 rounded text-xs">{{ formState.botUrl }}</code>
          </p>
          <p class="text-xs text-n-slate-11 mt-3">
            <strong>📝 Next:</strong> Enter your Typebot ID and click "Save Configuration" to link this bot to your Typebot flow.
          </p>
        </div>
      </div>

      <div v-if="showAccessTokenInput" class="flex flex-col gap-1">
        <label
          v-if="type === MODAL_TYPES.EDIT"
          class="mb-0.5 text-sm font-medium text-n-slate-12"
        >
          {{ $t('AGENT_BOTS.ACCESS_TOKEN.TITLE') }}
        </label>

        <AccessToken
          v-if="type === MODAL_TYPES.EDIT"
          :value="accessToken"
          @on-copy="onCopyToken"
          @on-reset="onResetToken"
        />
        <AccessToken
          v-else
          :value="accessToken"
          :show-reset-button="false"
          @on-copy="onCopyToken"
        />
      </div>

      <div class="flex items-center justify-end w-full gap-2 px-0 py-2">
        <NextButton
          faded
          slate
          type="reset"
          :label="showAccessToken ? $t('AGENT_BOTS.FORM.CANCEL') : $t('AGENT_BOTS.FORM.CANCEL')"
          @click="onClickClose()"
        />
        <NextButton
          v-if="!showAccessToken"
          type="submit"
          data-testid="label-submit"
          :label="confirmButtonLabel"
          :is-loading="isLoading"
          :disabled="v$.$invalid"
        />
        <!-- Save Configuration button (shown after bot creation or in edit mode) -->
        <NextButton
          v-else-if="showAccessToken || type === MODAL_TYPES.EDIT"
          @click="saveBotConfiguration"
          data-testid="label-save-config"
          label="Save Configuration"
          :is-loading="isSavingConfig"
          :disabled="!formState.typebotId || !formState.typebotId.trim()"
        />
      </div>
    </form>
  </Dialog>
</template>
