// Supabase legacy JSON을 정규 테이블로 변환해 적재하는 CLI 도구
import { readFile } from 'node:fs/promises';
import crypto from 'node:crypto';
import path from 'node:path';

const DEFAULT_CHUNK_ROWS = 200;
const VALID_EVENT_SOURCES = new Set(['web', 'admin', 'server', 'migration', 'dev']);
const VALID_TRADE_STATUS = new Set(['requested', 'accepted', 'rejected', 'cancelled', 'expired']);
const VALID_APPROVAL_STATUS = new Set(['pending', 'approved', 'rejected']);

const CARD_COLUMNS = [
  [1, '사랑'],
  [2, '희락'],
  [3, '화평'],
  [4, '오래참음'],
  [5, '자비'],
  [6, '양선'],
  [7, '충성'],
  [8, '온유'],
  [9, '절제'],
  [10, '히든'],
];

const CONDITION_KEY_MAP = new Map([
  ['signup', 'app_signup'],
  ['app_signup', 'app_signup'],
  ['card_3', 'card_3'],
  ['card_5', 'card_5'],
  ['card_10', 'card_10'],
]);

function parseArgs(argv) {
  const result = {
    file: '',
    apply: false,
    dryRun: true,
    chunkRows: DEFAULT_CHUNK_ROWS,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--file') {
      result.file = argv[++i] || '';
    } else if (arg === '--apply') {
      result.apply = true;
      result.dryRun = false;
    } else if (arg === '--dry-run') {
      result.apply = false;
      result.dryRun = true;
    } else if (arg === '--chunk-rows') {
      result.chunkRows = Number(argv[++i]) || DEFAULT_CHUNK_ROWS;
    } else if (arg === '--help' || arg === '-h') {
      printHelp();
      process.exit(0);
    } else if (!result.file && !arg.startsWith('--')) {
      result.file = arg;
    } else {
      throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!result.file) throw new Error('Missing required --file <export.json>');
  if (result.chunkRows < 1) throw new Error('--chunk-rows must be greater than 0');
  return result;
}

function printHelp() {
  console.log(`Usage:
  node beyond_us/tools/supabase_import/import_normalized_data.mjs --file <export.json> --dry-run
  node beyond_us/tools/supabase_import/import_normalized_data.mjs --file <export.json> --apply

Environment variables for --apply:
  SUPABASE_URL
  SUPABASE_SERVICE_ROLE_KEY
`);
}

async function readExportFile(filePath) {
  const absolutePath = path.resolve(filePath);
  const raw = await readFile(absolutePath, 'utf8');
  const data = JSON.parse(raw);
  validateExportPayload(data, absolutePath);
  return { data, absolutePath };
}

function validateExportPayload(data, absolutePath) {
  if (!data || typeof data !== 'object') throw new Error(`Invalid export JSON: ${absolutePath}`);
  if (data.exportVersion !== 1) throw new Error(`Unsupported exportVersion: ${data.exportVersion}`);
  if (data.sourceEnvironment !== 'dev' && data.sourceEnvironment !== 'prod') {
    throw new Error(`Invalid sourceEnvironment: ${data.sourceEnvironment}`);
  }
  if (!Array.isArray(data.sheets)) throw new Error('Invalid export JSON: sheets must be an array');
}

function buildImportModel(data, profileMap = null) {
  const issues = [];
  const addIssue = makeIssueCollector(data, issues);
  const profiles = buildProfiles(data, addIssue);
  const effectiveProfileMap = profileMap || makeDryRunProfileMap(profiles);

  const staticRows = {
    profiles,
    appSettings: buildAppSettings(data),
    tabSettings: buildTabSettings(data, addIssue),
    missionWeeks: buildMissionWeeks(data),
    missionItems: buildMissionItems(data),
    raffleConditions: buildRaffleConditions(data),
  };

  const relationalRows = {
    retreatAttendance: buildRetreatAttendance(data, effectiveProfileMap, addIssue),
    events: buildEvents(data, effectiveProfileMap, addIssue),
    userInventory: buildUserInventory(data, effectiveProfileMap, addIssue),
    userCards: buildUserCards(data, effectiveProfileMap, addIssue),
    userSummary: buildUserSummary(data, effectiveProfileMap, addIssue),
    missionProgress: buildMissionProgress(data, effectiveProfileMap, addIssue),
    raffleTickets: buildRaffleTickets(data, effectiveProfileMap, addIssue),
    holdPrayEntries: buildHoldPrayEntries(data, effectiveProfileMap),
    holdPrayGuesses: buildHoldPrayGuesses(data, effectiveProfileMap, addIssue),
    bbbAssignments: buildBbbAssignments(data, effectiveProfileMap, addIssue),
    bbbMessages: buildBbbMessages(data, effectiveProfileMap, addIssue),
    missionPhotoSubmissions: buildMissionPhotoSubmissions(data, effectiveProfileMap, addIssue),
    physicalCardReceipts: buildPhysicalCardReceipts(data, effectiveProfileMap, addIssue),
    trades: buildTrades(data, effectiveProfileMap, addIssue),
    tradePrayers: buildTradePrayers(data, effectiveProfileMap, addIssue),
    notices: buildNotices(data),
    inquiries: buildInquiries(data, effectiveProfileMap),
  };

  return {
    sourceEnvironment: data.sourceEnvironment,
    sourceSnapshotLabel: data.sourceSnapshotLabel || '',
    staticRows,
    relationalRows,
    issues,
    targetCounts: countTargets(staticRows, relationalRows, issues),
  };
}

function makeIssueCollector(data, issues) {
  return function addIssue(sheetName, rowNumber, severity, issueCode, message, payload = {}) {
    issues.push({
      source_environment: data.sourceEnvironment,
      sheet_name: sheetName || null,
      row_number: rowNumber || null,
      severity,
      issue_code: issueCode,
      message,
      payload,
    });
  };
}

function makeDryRunProfileMap(profiles) {
  const map = new Map();
  for (const profile of profiles) {
    map.set(profile.login_id, {
      id: uuidFromText(`dry-run:profile:${profile.login_id}`),
      login_id: profile.login_id,
      name: profile.name,
      parish: profile.parish,
    });
  }
  return map;
}

function sheetRows(data, sheetName) {
  const sheet = data.sheets.find((candidate) => candidate.sheetName === sheetName);
  return sheet && Array.isArray(sheet.rows) ? sheet.rows : [];
}

function buildProfiles(data, addIssue) {
  const rows = [];
  const seen = new Set();
  for (const [index, row] of sheetRows(data, 'Users').entries()) {
    const object = row.object || {};
    const loginId = text(object['닉네임']);
    if (!loginId) {
      addIssue('Users', row.rowNumber, 'error', 'missing_login_id', 'Users row has no nickname');
      continue;
    }
    if (seen.has(loginId)) {
      addIssue('Users', row.rowNumber, 'error', 'duplicate_login_id', `Duplicate login_id: ${loginId}`, { loginId });
      continue;
    }
    seen.add(loginId);

    const isDev = bool(object['isDev(개발자)']);
    const isStaff = bool(object.isStaff);
    const inactive = bool(object.inactive);
    const name = text(object['이름']) || loginId;
    const createdAt = timestampOrNull(object['가입일시']);

    rows.push({
      participant_no: index + 1,
      login_id: loginId,
      display_name: loginId,
      name,
      parish: text(object['소속']) || '미분류',
      role: isDev ? 'dev' : (isStaff ? 'admin' : 'user'),
      account_status: inactive ? 'inactive' : 'active',
      is_dev: isDev,
      is_test: /test|테스트/i.test(`${loginId} ${name}`),
      raffle_excluded: bool(object.raffleExcluded),
      password_migration_required: true,
      legacy_sheet_user_id: loginId,
      admin_note: text(object.inactiveAt) ? `inactiveAt=${text(object.inactiveAt)}` : null,
      created_at: createdAt || undefined,
    });
  }
  return rows;
}

function buildAppSettings(data) {
  const rows = [];
  for (const row of sheetRows(data, 'AppSettings')) {
    const object = row.object || {};
    const key = text(object.key);
    if (!key) continue;
    const valueType = text(object.type) || inferValueType(object.value);
    rows.push({
      key,
      value_json: normalizeSettingValue(object.value, valueType),
      value_type: valueType,
      note: text(object.note) || null,
    });
  }

  const bbbSettings = {};
  for (const row of sheetRows(data, 'BBBSettings')) {
    const object = row.object || {};
    const key = text(object.key);
    if (!key) continue;
    bbbSettings[key] = {
      open: bool(object.open),
      text: text(object.text),
    };
  }
  if (Object.keys(bbbSettings).length) {
    rows.push({
      key: 'bbb_settings',
      value_json: bbbSettings,
      value_type: 'json',
      note: 'BBBSettings 시트에서 이관한 섹션별 공개 상태',
    });
  }
  return rows;
}

function buildTabSettings(data, addIssue) {
  const map = new Map();
  for (const [index, row] of sheetRows(data, 'TabSettings').entries()) {
    const object = row.object || {};
    const key = text(object.tab_key);
    if (!key) continue;
    if (map.has(key)) {
      addIssue('TabSettings', row.rowNumber, 'warning', 'duplicate_tab_key', `Duplicate tab_key: ${key}`, { key });
    }
    const enabled = bool(object.enabled);
    const statusText = text(object.status);
    map.set(key, {
      tab_key: key,
      label: text(object.label) || key,
      enabled,
      status: statusText === 'open' || statusText === 'closed' ? statusText : (enabled ? 'open' : 'closed'),
      sort_order: (index + 1) * 10,
    });
  }
  return Array.from(map.values());
}

function buildMissionWeeks(data) {
  const map = new Map();
  for (const row of sheetRows(data, 'MissionDefinitions')) {
    const object = row.object || {};
    const weekKey = text(object.weekKey);
    if (!weekKey || map.has(weekKey)) continue;
    map.set(weekKey, {
      week_key: weekKey,
      week_order: int(object.weekOrder, 0),
      title: text(object.weekTitle) || weekKey,
      starts_on: dateOrNull(object.weekStartDate),
      ends_on: dateOrNull(object.weekEndDate),
      draw_threshold: int(object.drawThreshold, 6),
      enabled: boolDefault(object.enabled, true),
    });
  }
  return Array.from(map.values());
}

function buildMissionItems(data) {
  const rows = [];
  for (const row of sheetRows(data, 'MissionDefinitions')) {
    const object = row.object || {};
    const weekKey = text(object.weekKey);
    const itemNo = int(object.itemNo, 0);
    if (!weekKey || !itemNo) continue;
    rows.push({
      week_key: weekKey,
      item_no: itemNo,
      item_text: text(object.itemText),
      score_weight: int(object.scoreWeight, 1),
      category: text(object.category) || null,
      enabled: boolDefault(object.enabled, true),
    });
  }
  return rows;
}

function buildRaffleConditions(data) {
  const map = new Map([
    ['app_signup', { condition_key: 'app_signup', label: '앱 가입', enabled: true, sort_order: 1 }],
    ['card_3', { condition_key: 'card_3', label: '카드 3종 보유', enabled: true, sort_order: 2 }],
    ['card_5', { condition_key: 'card_5', label: '카드 5종 보유', enabled: true, sort_order: 3 }],
    ['card_10', { condition_key: 'card_10', label: '카드 10종 보유', enabled: true, sort_order: 4 }],
  ]);
  for (const row of sheetRows(data, 'RaffleTickets')) {
    const object = row.object || {};
    const key = normalizeConditionKey(object.condition);
    if (!key || map.has(key)) continue;
    map.set(key, {
      condition_key: key,
      label: text(object.condition_label) || key,
      enabled: true,
      sort_order: map.size + 1,
    });
  }
  return Array.from(map.values());
}

function buildRetreatAttendance(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'RetreatAttendance')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.nickname, 'RetreatAttendance', row.rowNumber, addIssue);
    if (!profile) continue;
    const attended = bool(object.attended);
    rows.push({
      profile_id: profile.id,
      attendance_status: attended ? 'attending' : 'pending',
      attended,
      updated_at: timestampOrNull(object.updatedAt) || undefined,
    });
  }
  return rows;
}

function buildEvents(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'Events')) {
    const object = row.object || {};
    const eventId = text(object.eventId);
    const profile = findProfile(profileMap, object.userId, 'Events', row.rowNumber, addIssue, { optional: true });
    const eventType = text(object.type);
    if (!eventType) continue;
    rows.push({
      id: isUuid(eventId) ? eventId : uuidFromText(`${data.sourceEnvironment}:Events:${row.rowNumber}:${eventId}`),
      occurred_at: timestampOrNull(object.timestamp) || undefined,
      profile_id: profile ? profile.id : null,
      event_type: eventType,
      ref_type: eventType.includes('.') ? eventType.split('.')[0] : null,
      ref_id: text(object.refId) || null,
      amount: int(object.amount, 0),
      week_key: text(object.weekKey) || null,
      payload: parseJsonObject(object.payload),
      source: normalizeEventSource(object.source),
    });
  }
  return rows;
}

function buildUserInventory(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'Collection')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'Collection', row.rowNumber, addIssue);
    if (!profile) continue;
    rows.push({
      profile_id: profile.id,
      normal_pack_earned: int(object['누적뽑기권'], 0),
      normal_pack_consumed: int(object['실제뽑은개수'], 0),
      normal_pack_remaining: int(object['남은개수'], 0),
      special_pack_earned: int(object.specialPackEarned, 0),
      special_pack_consumed: int(object.specialPackConsumed, 0),
      special_pack_remaining: int(object.specialPackRemaining, 0),
    });
  }
  return rows;
}

function buildUserCards(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'Collection')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'Collection', row.rowNumber, addIssue);
    if (!profile) continue;
    for (const [cardId, column] of CARD_COLUMNS) {
      const quantity = int(object[column], 0);
      if (quantity <= 0) continue;
      rows.push({
        profile_id: profile.id,
        card_id: cardId,
        quantity,
      });
    }
  }
  return rows;
}

function buildUserSummary(data, profileMap, addIssue) {
  const byProfile = new Map();
  for (const row of sheetRows(data, 'Collection')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'Collection', row.rowNumber, addIssue);
    if (!profile) continue;
    byProfile.set(profile.id, {
      profile_id: profile.id,
      total_cards: int(object['총카드수'], 0),
      raffle_ticket_count: int(object.raffleTickets, 0),
      payload: {
        source: 'Collection',
        raffleTicketNumbers: parseJsonArray(object.raffleTicketNumbersJson),
      },
    });
  }

  for (const row of sheetRows(data, 'UserDashboard')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'UserDashboard', row.rowNumber, addIssue);
    if (!profile) continue;
    const previous = byProfile.get(profile.id) || { profile_id: profile.id, payload: {} };
    byProfile.set(profile.id, {
      ...previous,
      mission_count: int(object.missionCount, previous.mission_count || 0),
      total_cards: int(object.totalCards, previous.total_cards || 0),
      active_trade_count: int(object.activeTrades, 0),
      last_activity_at: timestampOrNull(object.lastActivity),
      payload: {
        ...previous.payload,
        source: 'UserDashboard',
        ticketsEarned: int(object.ticketsEarned, 0),
        ticketsConsumed: int(object.ticketsConsumed, 0),
        ticketsRemaining: int(object.ticketsRemaining, 0),
        cardsDrawn: int(object.cardsDrawn, 0),
        specialPacksEarned: int(object.specialPacksEarned, 0),
        specialPacksConsumed: int(object.specialPacksConsumed, 0),
        specialPacksRemaining: int(object.specialPacksRemaining, 0),
      },
    });
  }

  return Array.from(byProfile.values()).map((row) => ({
    profile_id: row.profile_id,
    mission_count: row.mission_count || 0,
    total_cards: row.total_cards || 0,
    raffle_ticket_count: row.raffle_ticket_count || 0,
    active_trade_count: row.active_trade_count || 0,
    last_activity_at: row.last_activity_at || null,
    payload: row.payload || {},
  }));
}

function buildMissionProgress(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'MissionProgress')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'MissionProgress', row.rowNumber, addIssue);
    if (!profile) continue;
    const weekKey = text(object.weekKey);
    if (!weekKey) continue;
    rows.push({
      profile_id: profile.id,
      week_key: weekKey,
      total_score: int(object.totalScore, 0),
      date_keys: parseJsonArray(object.dateKeysJson),
      slot_counts: parseJsonObject(object.slotCountsJson),
      date_slot_indices: parseJsonObject(object.dateSlotIndicesJson),
      submission_event_count: int(object.submissionEventCount, 0),
      updated_at: timestampOrNull(object.updatedAt) || undefined,
    });
  }
  return rows;
}

function buildRaffleTickets(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'RaffleTickets')) {
    const object = row.object || {};
    const ticketNo = int(object.ticket_no, 0);
    if (!ticketNo) continue;
    const active = bool(object.active);
    const profile = findProfile(profileMap, object.userId, 'RaffleTickets', row.rowNumber, addIssue, { optional: !active });
    rows.push({
      ticket_no: ticketNo,
      active,
      profile_id: active && profile ? profile.id : null,
      condition_key: normalizeConditionKey(object.condition),
      issued_at: timestampOrNull(object.issued_at),
      revoked_at: active ? null : timestampOrNull(object.updated_at),
      revoked_reason: active ? null : 'legacy_inactive_ticket',
      updated_at: timestampOrNull(object.updated_at) || undefined,
    });
  }
  return rows;
}

function buildHoldPrayEntries(data, profileMap) {
  const rows = [];
  for (const row of sheetRows(data, 'HoldPray')) {
    const object = row.object || {};
    const content = text(object['기도제목(c)']);
    if (!content) continue;
    const profile = profileMap.get(text(object['닉네임(nick)'])) || null;
    rows.push({
      id: uuidFromText(`${data.sourceEnvironment}:HoldPray:${row.rowNumber}`),
      profile_id: profile ? profile.id : null,
      week_key: null,
      content,
      anonymous: bool(object['익명(a)']),
      visible: true,
      created_at: undefined,
    });
  }
  return rows;
}

function buildHoldPrayGuesses(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'HPGuesses')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.nickname, 'HPGuesses', row.rowNumber, addIssue);
    if (!profile) continue;
    const weekKey = text(object.weekKey);
    const cardIndex = int(object.cardIndex, -1);
    if (!weekKey || cardIndex < 0) continue;
    rows.push({
      profile_id: profile.id,
      week_key: weekKey,
      card_index: cardIndex,
      guessed_name: text(object.guessedName),
      answered_at: timestampOrNull(object.answeredAt) || undefined,
    });
  }
  return rows;
}

function buildBbbAssignments(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'BBB')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'BBB', row.rowNumber, addIssue);
    if (!profile) continue;
    const careBuddy = findProfile(profileMap, object.careBuddyId, 'BBB', row.rowNumber, addIssue, { optional: true });
    const secretBuddy = findProfile(profileMap, object.secretBuddyId, 'BBB', row.rowNumber, addIssue, { optional: true });
    rows.push({
      profile_id: profile.id,
      care_buddy_id: careBuddy ? careBuddy.id : null,
      secret_buddy_id: secretBuddy ? secretBuddy.id : null,
      secret_revealed: bool(object.secretRevealed),
    });
  }
  return rows;
}

function buildBbbMessages(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'BBBMessages')) {
    const object = row.object || {};
    const fromProfile = findProfile(profileMap, object.fromUserId, 'BBBMessages', row.rowNumber, addIssue);
    const toProfile = findProfile(profileMap, object.toUserId, 'BBBMessages', row.rowNumber, addIssue);
    const message = text(object.message);
    if (!fromProfile || !toProfile || !message) continue;
    rows.push({
      id: uuidFromText(`${data.sourceEnvironment}:BBBMessages:${text(object.msgId) || row.rowNumber}`),
      from_profile_id: fromProfile.id,
      to_profile_id: toProfile.id,
      message,
      created_at: timestampOrNull(object.createdAt) || undefined,
    });
  }
  return rows;
}

function buildMissionPhotoSubmissions(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'BBBPhotos')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.userId, 'BBBPhotos', row.rowNumber, addIssue);
    if (!profile) continue;
    const missionKey = text(object.missionType);
    if (!missionKey) continue;
    const approvedBy = findProfile(profileMap, object.approvedBy, 'BBBPhotos', row.rowNumber, addIssue, { optional: true });
    const approvalStatus = normalizeApprovalStatus(object.approvalStatus);
    rows.push({
      id: uuidFromText(`${data.sourceEnvironment}:BBBPhotos:${row.rowNumber}:${profile.id}:${missionKey}`),
      profile_id: profile.id,
      mission_key: missionKey,
      spot_index: null,
      storage_path: `legacy://BBBPhotos/${row.rowNumber}`,
      approval_status: approvalStatus,
      approved_at: approvalStatus === 'approved' ? timestampOrNull(object.approvedAt) : null,
      approved_by: approvedBy ? approvedBy.id : null,
      rejected_at: approvalStatus === 'rejected' ? timestampOrNull(object.approvedAt) : null,
      reward_event_id: isUuid(text(object.rewardEventId)) ? text(object.rewardEventId) : null,
      created_at: timestampOrNull(object.uploadedAt) || undefined,
    });
  }
  return rows;
}

function buildPhysicalCardReceipts(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'CardReceived')) {
    const object = row.object || {};
    const profile = findProfile(profileMap, object.nickname, 'CardReceived', row.rowNumber, addIssue);
    const cardId = int(object.cardId, 0);
    if (!profile || !cardId) continue;
    rows.push({
      profile_id: profile.id,
      card_id: cardId,
      received_qty: int(object.receivedQty, 0),
      updated_at: timestampOrNull(object.updatedAt) || undefined,
    });
  }
  return rows;
}

function buildTrades(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'Trades')) {
    const object = row.object || {};
    const requester = findProfile(profileMap, object.requester, 'Trades', row.rowNumber, addIssue);
    const target = findProfile(profileMap, object.target, 'Trades', row.rowNumber, addIssue);
    if (!requester || !target) continue;
    rows.push({
      id: uuidFromText(`${data.sourceEnvironment}:Trades:${text(object.id) || row.rowNumber}`),
      requester_id: requester.id,
      requester_card_id: int(object.requesterCardId, 0),
      target_id: target.id,
      target_card_id: int(object.targetCardId, 0),
      status: normalizeTradeStatus(object.status),
      created_at: timestampOrNull(object.createdAt) || undefined,
      resolved_at: timestampOrNull(object.resolvedAt),
    });
  }
  return rows;
}

function buildTradePrayers(data, profileMap, addIssue) {
  const rows = [];
  for (const row of sheetRows(data, 'Trades')) {
    const object = row.object || {};
    const tradeId = uuidFromText(`${data.sourceEnvironment}:Trades:${text(object.id) || row.rowNumber}`);
    const requester = findProfile(profileMap, object.requester, 'Trades', row.rowNumber, addIssue, { optional: true });
    const target = findProfile(profileMap, object.target, 'Trades', row.rowNumber, addIssue, { optional: true });
    if (requester && timestampOrNull(object.requesterPrayed)) {
      rows.push({ trade_id: tradeId, profile_id: requester.id, prayed_at: timestampOrNull(object.requesterPrayed) });
    }
    if (target && timestampOrNull(object.targetPrayed)) {
      rows.push({ trade_id: tradeId, profile_id: target.id, prayed_at: timestampOrNull(object.targetPrayed) });
    }
  }
  return rows;
}

function buildNotices(data) {
  const rows = [];
  for (const row of sheetRows(data, 'Notices')) {
    const object = row.object || {};
    const title = text(object.title);
    const content = text(object.content);
    if (!title || !content) continue;
    rows.push({
      id: uuidFromText(`${data.sourceEnvironment}:Notices:${text(object.id) || row.rowNumber}`),
      title,
      content,
      image_path: text(object.column_5) || null,
      visible: true,
      created_at: timestampOrNull(object.createdAt) || undefined,
      updated_at: timestampOrNull(object.updatedAt) || undefined,
    });
  }
  return rows;
}

function buildInquiries(data, profileMap) {
  const rows = [];
  for (const row of sheetRows(data, 'Inquiries')) {
    const object = row.object || {};
    const content = text(object.content);
    if (!content) continue;
    const profile = profileMap.get(text(object.nickname)) || null;
    const reply = text(object.reply);
    rows.push({
      id: uuidFromText(`${data.sourceEnvironment}:Inquiries:${text(object.id) || row.rowNumber}`),
      profile_id: profile ? profile.id : null,
      content,
      reply: reply || null,
      replied_at: timestampOrNull(object.repliedAt),
      status: reply ? 'replied' : 'open',
      created_at: timestampOrNull(object.createdAt) || undefined,
    });
  }
  return rows;
}

function findProfile(profileMap, value, sheetName, rowNumber, addIssue, options = {}) {
  const key = text(value);
  if (!key) {
    if (!options.optional) addIssue(sheetName, rowNumber, 'warning', 'missing_user_ref', 'Missing user reference');
    return null;
  }
  const profile = profileMap.get(key);
  if (!profile && !options.optional) {
    addIssue(sheetName, rowNumber, 'warning', 'unknown_user_ref', `Unknown user reference: ${key}`, { userId: key });
  }
  return profile || null;
}

function countTargets(staticRows, relationalRows, issues) {
  const counts = {};
  for (const [key, rows] of Object.entries(staticRows)) counts[key] = rows.length;
  for (const [key, rows] of Object.entries(relationalRows)) counts[key] = rows.length;
  counts.migrationIssues = issues.length;
  return counts;
}

function getSupabaseConfig() {
  const url = normalizeSupabaseUrl(process.env.SUPABASE_URL);
  const serviceRoleKey = String(process.env.SUPABASE_SERVICE_ROLE_KEY || '');
  if (!url) throw new Error('Missing SUPABASE_URL');
  if (!serviceRoleKey) throw new Error('Missing SUPABASE_SERVICE_ROLE_KEY');
  return { url, serviceRoleKey };
}

function normalizeSupabaseUrl(value) {
  const raw = String(value || '').trim();
  if (!raw) return '';
  let url;
  try {
    url = new URL(raw);
  } catch {
    throw new Error('Invalid SUPABASE_URL. Use the project URL like https://<project-ref>.supabase.co');
  }
  url.pathname = url.pathname.replace(/\/rest\/v1\/?$/i, '');
  url.pathname = url.pathname.replace(/\/+$/, '');
  url.search = '';
  url.hash = '';
  return url.toString().replace(/\/+$/, '');
}

async function supabaseFetch(config, endpoint, options = {}) {
  const response = await fetch(`${config.url}/rest/v1/${endpoint}`, {
    ...options,
    headers: {
      apikey: config.serviceRoleKey,
      Authorization: `Bearer ${config.serviceRoleKey}`,
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  });

  const textBody = await response.text();
  const body = textBody ? safeJson(textBody) : null;
  if (!response.ok) {
    const detail = typeof body === 'string' ? body : JSON.stringify(body);
    throw new Error(`Supabase request failed ${response.status} ${endpoint}: ${detail}`);
  }
  return body;
}

async function upsertRows(config, table, rows, onConflict, chunkRows) {
  if (!rows.length) return { table, rows: 0, chunks: 0 };
  let chunks = 0;
  let inserted = 0;
  const endpoint = `${table}?on_conflict=${encodeURIComponent(onConflict)}`;
  for (const chunk of chunkArray(rows, chunkRows)) {
    await supabaseFetch(config, endpoint, {
      method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(stripUndefined(chunk)),
    });
    chunks += 1;
    inserted += chunk.length;
  }
  return { table, rows: inserted, chunks };
}

async function insertRows(config, table, rows, chunkRows) {
  if (!rows.length) return { table, rows: 0, chunks: 0 };
  let chunks = 0;
  let inserted = 0;
  for (const chunk of chunkArray(rows, chunkRows)) {
    await supabaseFetch(config, table, {
      method: 'POST',
      headers: { Prefer: 'return=minimal' },
      body: JSON.stringify(stripUndefined(chunk)),
    });
    chunks += 1;
    inserted += chunk.length;
  }
  return { table, rows: inserted, chunks };
}

async function createMigrationBatch(config, data, model) {
  const payload = {
    source_environment: data.sourceEnvironment,
    source_spreadsheet_id: data.sourceSpreadsheetId || null,
    source_snapshot_label: data.sourceSnapshotLabel || null,
    status: 'running',
    started_at: new Date().toISOString(),
    row_counts: {
      source: data.rowCounts || {},
      targets: model.targetCounts,
    },
    notes: 'normalized table import',
  };

  const created = await supabaseFetch(config, 'migration_batches', {
    method: 'POST',
    headers: { Prefer: 'return=representation' },
    body: JSON.stringify(payload),
  });
  if (!Array.isArray(created) || !created[0] || !created[0].id) {
    throw new Error('Failed to create migration batch');
  }
  return created[0].id;
}

async function updateMigrationBatch(config, batchId, status, rowCounts, notes = null) {
  await supabaseFetch(config, `migration_batches?id=eq.${encodeURIComponent(batchId)}`, {
    method: 'PATCH',
    headers: { Prefer: 'return=minimal' },
    body: JSON.stringify({
      status,
      completed_at: new Date().toISOString(),
      row_counts: rowCounts,
      notes,
    }),
  });
}

async function fetchProfiles(config) {
  const rows = await fetchAll(config, 'profiles?select=id,login_id,name,parish,account_status,raffle_excluded&order=participant_no.asc');
  const map = new Map();
  for (const row of rows) map.set(row.login_id, row);
  return map;
}

async function fetchAll(config, endpoint, pageSize = 1000) {
  const results = [];
  for (let offset = 0; ; offset += pageSize) {
    const separator = endpoint.includes('?') ? '&' : '?';
    const page = await supabaseFetch(config, `${endpoint}${separator}limit=${pageSize}&offset=${offset}`);
    if (!Array.isArray(page) || !page.length) break;
    results.push(...page);
    if (page.length < pageSize) break;
  }
  return results;
}

async function applyModel(config, data, initialModel, chunkRows) {
  const batchId = await createMigrationBatch(config, data, initialModel);
  const operations = [];

  try {
    operations.push(await upsertRows(config, 'profiles', initialModel.staticRows.profiles, 'login_id', chunkRows));
    operations.push(await upsertRows(config, 'app_settings', initialModel.staticRows.appSettings, 'key', chunkRows));
    operations.push(await upsertRows(config, 'tab_settings', initialModel.staticRows.tabSettings, 'tab_key', chunkRows));
    operations.push(await upsertRows(config, 'mission_weeks', initialModel.staticRows.missionWeeks, 'week_key', chunkRows));
    operations.push(await upsertRows(config, 'mission_items', initialModel.staticRows.missionItems, 'week_key,item_no', chunkRows));
    operations.push(await upsertRows(config, 'raffle_conditions', initialModel.staticRows.raffleConditions, 'condition_key', chunkRows));

    const profileMap = await fetchProfiles(config);
    const model = buildImportModel(data, profileMap);

    operations.push(await upsertRows(config, 'retreat_attendance', model.relationalRows.retreatAttendance, 'profile_id', chunkRows));
    operations.push(await upsertRows(config, 'events', model.relationalRows.events, 'id', chunkRows));
    operations.push(await upsertRows(config, 'user_inventory', model.relationalRows.userInventory, 'profile_id', chunkRows));
    operations.push(await upsertRows(config, 'user_cards', model.relationalRows.userCards, 'profile_id,card_id', chunkRows));
    operations.push(await upsertRows(config, 'user_summary', model.relationalRows.userSummary, 'profile_id', chunkRows));
    operations.push(await upsertRows(config, 'mission_progress', model.relationalRows.missionProgress, 'profile_id,week_key', chunkRows));
    operations.push(await upsertRows(config, 'raffle_tickets', model.relationalRows.raffleTickets, 'ticket_no', chunkRows));
    operations.push(await upsertRows(config, 'hold_pray_entries', model.relationalRows.holdPrayEntries, 'id', chunkRows));
    operations.push(await upsertRows(config, 'hold_pray_guesses', model.relationalRows.holdPrayGuesses, 'profile_id,week_key,card_index', chunkRows));
    operations.push(await upsertRows(config, 'bbb_assignments', model.relationalRows.bbbAssignments, 'profile_id', chunkRows));
    operations.push(await upsertRows(config, 'bbb_messages', model.relationalRows.bbbMessages, 'id', chunkRows));
    operations.push(await upsertRows(config, 'mission_photo_submissions', model.relationalRows.missionPhotoSubmissions, 'id', chunkRows));
    operations.push(await upsertRows(config, 'physical_card_receipts', model.relationalRows.physicalCardReceipts, 'profile_id,card_id', chunkRows));
    operations.push(await upsertRows(config, 'trades', model.relationalRows.trades, 'id', chunkRows));
    operations.push(await upsertRows(config, 'trade_prayers', model.relationalRows.tradePrayers, 'trade_id,profile_id', chunkRows));
    operations.push(await upsertRows(config, 'notices', model.relationalRows.notices, 'id', chunkRows));
    operations.push(await upsertRows(config, 'inquiries', model.relationalRows.inquiries, 'id', chunkRows));

    const issues = model.issues.map((issue) => ({ ...issue, batch_id: batchId }));
    operations.push(await insertRows(config, 'migration_issues', issues, chunkRows));

    const rowCounts = {
      source: data.rowCounts || {},
      targets: model.targetCounts,
      operations,
    };
    await updateMigrationBatch(config, batchId, 'completed', rowCounts, 'normalized table import completed');
    return { batchId, rowCounts };
  } catch (error) {
    await updateMigrationBatch(config, batchId, 'failed', initialModel.targetCounts, `normalized table import failed: ${error.message}`);
    throw error;
  }
}

function text(value) {
  if (value === null || value === undefined) return '';
  return String(value).trim();
}

function bool(value) {
  if (value === true || value === 1) return true;
  if (value === false || value === 0 || value === null || value === undefined || value === '') return false;
  const normalized = String(value).trim().toLowerCase();
  return ['true', '1', 'yes', 'y', 'checked', '✓'].includes(normalized);
}

function boolDefault(value, defaultValue) {
  if (value === null || value === undefined || value === '') return defaultValue;
  return bool(value);
}

function int(value, fallback) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : fallback;
}

function timestampOrNull(value) {
  const raw = text(value);
  if (!raw) return null;
  const date = new Date(raw);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

function dateOrNull(value) {
  const iso = timestampOrNull(value);
  return iso ? iso.slice(0, 10) : null;
}

function inferValueType(value) {
  if (typeof value === 'boolean') return 'boolean';
  if (typeof value === 'number') return 'number';
  if (value && typeof value === 'object') return 'json';
  return 'string';
}

function normalizeSettingValue(value, valueType) {
  if (valueType === 'number') return Number(value) || 0;
  if (valueType === 'boolean') return bool(value);
  if (valueType === 'json') return parseJsonValue(value);
  return value === undefined ? null : value;
}

function parseJsonValue(value) {
  if (value === null || value === undefined || value === '') return null;
  if (typeof value !== 'string') return value;
  return safeJson(value);
}

function parseJsonObject(value) {
  const parsed = parseJsonValue(value);
  if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
  if (parsed === null || parsed === undefined || parsed === '') return {};
  return { value: parsed };
}

function parseJsonArray(value) {
  const parsed = parseJsonValue(value);
  return Array.isArray(parsed) ? parsed : [];
}

function safeJson(value) {
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

function normalizeEventSource(value) {
  const source = text(value);
  return VALID_EVENT_SOURCES.has(source) ? source : 'migration';
}

function normalizeConditionKey(value) {
  const key = text(value);
  if (!key) return null;
  return CONDITION_KEY_MAP.get(key) || key;
}

function normalizeTradeStatus(value) {
  const status = text(value);
  return VALID_TRADE_STATUS.has(status) ? status : 'requested';
}

function normalizeApprovalStatus(value) {
  const status = text(value);
  return VALID_APPROVAL_STATUS.has(status) ? status : 'pending';
}

function isUuid(value) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(text(value));
}

function uuidFromText(value) {
  const bytes = crypto.createHash('sha256').update(String(value)).digest();
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex').slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

function chunkArray(rows, size) {
  const chunks = [];
  for (let index = 0; index < rows.length; index += size) {
    chunks.push(rows.slice(index, index + size));
  }
  return chunks;
}

function stripUndefined(value) {
  return JSON.parse(JSON.stringify(value));
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const { data, absolutePath } = await readExportFile(args.file);
  const model = buildImportModel(data);

  if (args.dryRun) {
    console.log(JSON.stringify({
      ok: true,
      mode: 'dry-run',
      file: absolutePath,
      sourceEnvironment: data.sourceEnvironment,
      sourceSnapshotLabel: data.sourceSnapshotLabel || '',
      sourceRowCounts: data.rowCounts || {},
      targetCounts: model.targetCounts,
      issuePreview: model.issues.slice(0, 20),
    }, null, 2));
    return;
  }

  const config = getSupabaseConfig();
  const result = await applyModel(config, data, model, args.chunkRows);
  console.log(JSON.stringify({
    ok: true,
    mode: 'apply',
    sourceEnvironment: data.sourceEnvironment,
    sourceSnapshotLabel: data.sourceSnapshotLabel || '',
    batchId: result.batchId,
    targetCounts: result.rowCounts.targets,
    operations: result.rowCounts.operations,
  }, null, 2));
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
