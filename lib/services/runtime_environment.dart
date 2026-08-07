const String runtimeOpenAiBaseUrl = String.fromEnvironment(
  'OPENAI_BASE_URL',
);

const String runtimeOpenAiModel = String.fromEnvironment(
  'OPENAI_MODEL',
);

const String runtimeAppLabel = String.fromEnvironment(
  'APP_LABEL',
  defaultValue: 'tutor',
);

const bool runtimeIsAgentTutor = runtimeAppLabel == 'agent_tutor';

const String runtimeAppTitle =
    runtimeIsAgentTutor ? 'Agent Tutor' : 'Tutor1on1';

const String runtimePlatform = 'web';
