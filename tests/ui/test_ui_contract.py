# SPDX-License-Identifier: MIT
"""Independent static and sizing tests for the clean-room companion UI."""

from __future__ import annotations

import re
import json
import unittest
from pathlib import Path


PROJECT = Path(__file__).resolve().parents[2]
PAYLOAD = PROJECT / "SurvivorCompanion"
CLIENT = PROJECT / "SurvivorCompanion" / "42" / "media" / "lua" / "client"
TRANSLATE = PROJECT / "SurvivorCompanion" / "42" / "media" / "lua" / "shared" / "Translate"

FROZEN_GAMEPLAY_KEYS = {
    "IGUI_SC_Dismiss_Response",
    "IGUI_SC_Memory_None",
    "IGUI_SC_Recruit_Response",
    "IGUI_SC_Status_Response",
    "UI_SC_Status_Bleeding",
    "UI_SC_Status_Dead",
    "UI_SC_Status_Downed",
    "UI_SC_Status_Knox",
    "UI_SC_Status_NoKnox",
    "UI_SC_Status_Stable",
    "UI_SC_Status_TerminalKnox",
    "UI_SC_Status_Unavailable",
    "UI_SC_Status_Wounded",
    "UI_SC_UnknownCompanion",
}


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def payload_lua_sources() -> list[tuple[Path, str]]:
    return [(path, read(path)) for path in sorted(PAYLOAD.rglob("*.lua"))]


def literal_gettext_keys(source: str) -> set[str]:
    direct = re.findall(
        r"\b(?:getText|getTextOrNull)\s*\(\s*[\"']([^\"']+)[\"']",
        source,
    )
    protected = re.findall(
        r"\bpcall\s*\(\s*(?:getText|getTextOrNull)\s*,\s*[\"']([^\"']+)[\"']",
        source,
    )
    return set(direct + protected)


def project_translation_literals(source: str) -> set[str]:
    return set(re.findall(r"[\"']((?:UI|IGUI)_SC_[A-Za-z0-9_]+)[\"']", source))


def dynamic_translation_patterns(source: str) -> set[str]:
    return set(
        re.findall(
            r"[\"']((?:UI|IGUI)_SC_[A-Za-z0-9_]+)[\"']\s*\.\.",
            source,
        )
    )


def defaults() -> dict[str, float]:
    source = read(CLIENT / "SCUIBounds.lua")
    block = re.search(r"Bounds\.defaults\s*=\s*\{(.*?)\n\}", source, re.S)
    if not block:
        raise AssertionError("Bounds.defaults table not found")
    values: dict[str, float] = {}
    for name, value in re.findall(r"(\w+)\s*=\s*([0-9.]+)", block.group(1)):
        values[name] = float(value)
    return values


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def layout_metrics(font_height: int) -> dict[str, int]:
    line_height = font_height + 4
    button_height = max(26, font_height + 12)
    return {
        "font_height": font_height,
        "line_height": line_height,
        "info_line_height": font_height + 5,
        "section_height": font_height + 10,
        "button_height": button_height,
        "tab_height": button_height,
        "header_height": max(36, button_height + 10),
        "roster_item_height": line_height * 4 + 10,
    }


def model_layout(
    width: int,
    height: int,
    font_height: int,
    character_width: int,
    tab_labels: list[str],
) -> dict[str, int]:
    metrics = layout_metrics(font_height)
    roster_width = int(clamp(int(width * 0.39), 145, 210))
    detail_x = roster_width + 12
    detail_width = width - detail_x - 6
    maximum_label_width = max(len(label) * character_width + 16 for label in tab_labels)
    columns = 3
    while columns > 1 and detail_width // columns < maximum_label_width:
        columns -= 1
    rows = (len(tab_labels) + columns - 1) // columns
    tab_top = metrics["header_height"] + 1
    detail_y = tab_top + rows * metrics["tab_height"] + 3
    return {
        **metrics,
        "roster_width": roster_width,
        "detail_x": detail_x,
        "detail_width": detail_width,
        "tab_columns": columns,
        "tab_rows": rows,
        "tab_top": tab_top,
        "detail_y": detail_y,
        "detail_height": height - detail_y - 7,
    }


def orders_content_height(font_height: int) -> int:
    metrics = layout_metrics(font_height)
    section_count = 5
    command_count = 18
    inter_section_gaps = 4 * 4
    bottom = (
        7
        + section_count * metrics["section_height"]
        + inter_section_gaps
        + command_count * (metrics["button_height"] + 4)
    )
    return bottom + 8


def lua_function(source: str, signature: str) -> str:
    start = source.index(signature)
    next_function = re.search(r"\n(?:local\s+)?function\s+", source[start + len(signature) :])
    if not next_function:
        return source[start:]
    end = start + len(signature) + next_function.start()
    return source[start:end]


class UISizingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.d = defaults()

    def expanded_width(self, screen_width: int) -> int:
        requested = int(screen_width * self.d["expandedRatio"] + 0.5)
        return int(clamp(requested, self.d["expandedMinWidth"], self.d["expandedMaxWidth"]))

    def expanded_height(self, screen_height: int, saved: int | None = None) -> int:
        maximum = int(screen_height - self.d["safeVerticalMargin"] * 2)
        minimum = int(min(self.d["expandedMinHeight"], maximum))
        requested = saved if saved is not None else int(self.d["expandedDefaultHeight"])
        return int(clamp(requested, minimum, maximum))

    def expanded_rect(
        self,
        screen_width: int,
        screen_height: int,
        dock: str,
        y: int,
        saved_width: int | None = None,
        saved_height: int | None = None,
    ) -> tuple[int, int, int, int]:
        width = (
            int(clamp(saved_width, self.d["expandedMinWidth"], self.d["expandedMaxWidth"]))
            if saved_width is not None
            else self.expanded_width(screen_width)
        )
        height = self.expanded_height(screen_height, saved_height)
        margin = int(self.d["safeVerticalMargin"])
        clamped_y = int(clamp(y, margin, screen_height - margin - height))
        x = 0 if dock == "left" else screen_width - width
        return x, clamped_y, width, height

    def test_acceptance_resolution_widths(self) -> None:
        self.assertEqual(self.expanded_width(1280), 410)
        self.assertEqual(self.expanded_width(1920), 560)
        self.assertEqual(self.expanded_width(2560), 560)

    def test_exact_collapsed_dimensions(self) -> None:
        self.assertEqual(self.d["collapsedWidth"], 54)
        self.assertEqual(self.d["collapsedMaxWidth"], 84)
        self.assertEqual(self.d["collapsedHeight"], 112)
        self.assertEqual(self.d["collapsedMaxHeight"], 148)
        self.assertEqual(
            int(clamp(round(3840 * self.d["collapsedWidthRatio"]),
                      self.d["collapsedWidth"], self.d["collapsedMaxWidth"])),
            84,
        )
        self.assertEqual(
            int(clamp(round(2160 * self.d["collapsedHeightRatio"]),
                      self.d["collapsedHeight"], self.d["collapsedMaxHeight"])),
            130,
        )

    def test_default_tab_is_near_quarter_screen_height(self) -> None:
        for height in (720, 1080, 1440):
            y = int(height * self.d["defaultEdgeRatio"] + 0.5)
            self.assertEqual(y, round(height * 0.25))
            self.assertGreaterEqual(y, self.d["safeVerticalMargin"])
            self.assertLessEqual(
                y + self.d["collapsedHeight"],
                height - self.d["safeVerticalMargin"],
            )

    def test_maximum_height_is_screen_minus_80(self) -> None:
        margin = self.d["safeVerticalMargin"]
        self.assertEqual(margin * 2, 80)
        for height in (720, 1080, 1440):
            self.assertEqual(height - margin * 2, height - 80)
            self.assertEqual(self.expanded_height(height, 9999), height - 80)

    def test_left_and_right_docking_are_edge_aligned(self) -> None:
        for screen_width, screen_height in ((1280, 720), (1920, 1080), (2560, 1440)):
            left = self.expanded_rect(screen_width, screen_height, "left", -500)
            right = self.expanded_rect(screen_width, screen_height, "right", 9999)
            self.assertEqual(left[0], 0)
            self.assertEqual(right[0] + right[2], screen_width)
            self.assertEqual(left[1], self.d["safeVerticalMargin"])
            self.assertEqual(
                right[1] + right[3],
                screen_height - self.d["safeVerticalMargin"],
            )

    def test_saved_dimensions_are_reclamped(self) -> None:
        narrow = self.expanded_rect(1280, 720, "right", 40, 1, 1)
        wide = self.expanded_rect(1280, 720, "right", 40, 9999, 9999)
        self.assertEqual(narrow[2], 380)
        self.assertEqual(narrow[3], 360)
        self.assertEqual(wide[2], 560)
        self.assertEqual(wide[3], 640)

    def test_orders_content_exceeds_the_720p_viewport(self) -> None:
        en_data = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        labels = [
            en_data[f"UI_SC_Tab_{name}"]
            for name in ("Status", "Orders", "Loadout", "Base", "More")
        ]
        layout = model_layout(410, 600, 14, 7, labels)
        content_height = orders_content_height(14)
        self.assertEqual(layout["detail_height"], 501)
        self.assertGreaterEqual(content_height, 670)
        self.assertLessEqual(content_height, 710)
        self.assertGreater(content_height, layout["detail_height"])
        self.assertGreater(content_height - layout["detail_height"], 0)

    def test_small_and_large_fonts_do_not_overlap_at_minimum_sizes(self) -> None:
        en_data = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        tab_labels = [
            en_data[f"UI_SC_Tab_{name}"]
            for name in ("Status", "Orders", "Loadout", "Base", "More")
        ]
        action_labels = [
            value
            for key, value in en_data.items()
            if key.startswith("UI_SC_Action_")
        ]
        for width in (380, 410):
            for font_height, character_width in ((14, 7), (24, 12)):
                with self.subTest(width=width, font_height=font_height):
                    layout = model_layout(width, 600, font_height, character_width, tab_labels)
                    self.assertGreaterEqual(layout["button_height"], font_height + 2)
                    self.assertGreaterEqual(layout["tab_height"], font_height + 2)
                    self.assertGreater(layout["roster_item_height"], 4 * layout["line_height"])
                    self.assertLessEqual(5 + layout["button_height"], layout["header_height"])
                    last_tab_bottom = layout["tab_top"] + layout["tab_rows"] * layout["tab_height"]
                    self.assertLess(last_tab_bottom, layout["detail_y"])
                    self.assertGreater(layout["detail_height"], 300)

                    for label in action_labels:
                        measured = len(label) * character_width
                        available = max(100, layout["detail_width"] - 28)
                        button_width = available
                        content_width = layout["detail_width"]
                        self.assertLessEqual(button_width + 8, content_width)
                        self.assertEqual(content_width, layout["detail_width"])
                    self.assertGreater(orders_content_height(font_height), layout["detail_height"])


class UIStaticContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.ui = read(CLIENT / "SCUI.lua")
        cls.context = read(CLIENT / "SCUIContext.lua")
        cls.bounds = read(CLIENT / "SCUIBounds.lua")
        cls.bridge = read(CLIENT / "SCUIBridge.lua")
        cls.format = read(CLIENT / "SCUIFormat.lua")
        cls.pixels = read(CLIENT / "SCUIPixels.lua")
        cls.translations = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        cls.all_source = "\n".join((cls.ui, cls.context, cls.bounds, cls.bridge, cls.format, cls.pixels))

    def test_no_independent_tick_loop(self) -> None:
        self.assertNotIn("Events.OnTick", self.all_source)
        self.assertNotRegex(self.all_source, r"OnTick\s*\.\s*Add")

    def test_resolution_reclamp_occurs_in_prerender(self) -> None:
        self.assertIn("function SCUIRoot:prerender()", self.ui)
        self.assertIn("self:applyScreenBounds()", self.ui)
        self.assertIn("sw ~= self.lastScreenWidth", self.ui)
        self.assertIn("sh ~= self.lastScreenHeight", self.ui)

    def test_docked_geometry_sizes_before_positioning(self) -> None:
        apply_rect = lua_function(self.ui, "function SCUIRoot:applyRect(rect)")
        self.assertLess(apply_rect.index("self:setWidth(rect.width)"),
                        apply_rect.index("self:setX(rect.x)"))
        self.assertLess(apply_rect.index("self:setHeight(rect.height)"),
                        apply_rect.index("self:setY(rect.y)"))
        for signature in (
            "function SCUIRoot:setCollapsed(collapsed, initial)",
            "function SCUIRoot:applyScreenBounds()",
        ):
            self.assertIn("self:applyRect(rect)", lua_function(self.ui, signature))
        resize = lua_function(self.ui, "function SCUIRoot:onMouseMove(dx, dy)")
        self.assertIn("self:applyRect(rect)", resize)

        # Reproduce the Build 42 keep-on-screen clamp that caused the report:
        # setX while width=560 clamps 3756 to 3280; width-first preserves 3756.
        screen, expanded, collapsed = 3840, 560, 84
        desired = screen - collapsed
        old_order_x = min(desired, screen - expanded)
        new_order_x = min(desired, screen - collapsed)
        self.assertEqual(old_order_x, 3280)
        self.assertEqual(new_order_x, 3756)

    def test_collapse_uses_a_separate_launcher_without_click_through(self) -> None:
        collapse = lua_function(
            self.ui, "function SCUIRoot:setCollapsed(collapsed, initial)"
        )
        root_mouse_up = lua_function(self.ui, "function SCUIRoot:onMouseUp(x, y)")
        launcher_mouse_up = lua_function(
            self.ui, "function SCUICollapsedLauncher:onMouseUp(x, y)"
        )
        ensure = lua_function(self.ui, "function UI.ensureControl()")

        self.assertIn('ISPanel:derive("SCUICollapsedLauncher")', self.ui)
        self.assertIn("self:setVisible(false)", collapse)
        self.assertIn("UI.showCollapsedLauncher(self)", collapse)
        self.assertIn("self.root:setCollapsed(false)", launcher_mouse_up)
        self.assertIn("if not self.dragging then return false end", launcher_mouse_up)
        self.assertNotIn("setCollapsed(false)", root_mouse_up)
        self.assertIn("Bounds.expandedRect", ensure)
        self.assertNotIn("Bounds.collapsedRect", ensure)

    def test_required_tabs_are_present(self) -> None:
        for tab in ("status", "orders", "loadout", "base", "more", "journal",
                    "groups", "factions", "support"):
            self.assertRegex(self.ui, rf'\"{tab}\"')

    def test_debug_tab_is_private_build_only(self) -> None:
        tab_ids = lua_function(self.ui, "function UI.tabIds()")
        self.assertIn('SC.Config.get("debugSpawnEnabled") == true', tab_ids)
        self.assertIn('result[#result + 1] = "debug"', tab_ids)
        self.assertNotRegex(self.ui, r'local TAB_IDS\s*=\s*\{[^}]*"debug"')

    def test_debug_spawn_exposes_house_coordinates_and_world_locator(self) -> None:
        debug = lua_function(self.ui, "function SCUIDetail:buildDebug(panel)")
        handler = lua_function(self.ui, "local function onFactionButton(target, button)")
        locator = lua_function(self.ui, "function UI.locateDebugFactionHouse(factionId)")
        self.assertIn("UI.debugHouseLocation", debug)
        self.assertIn('"locate_house", id', debug)
        self.assertIn('action == "locate_house"', handler)
        self.assertIn("addGridSquareMarker", locator)
        self.assertIn("addPlayerHomingPoint", locator)
        translations = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        for key in (
            "UI_SC_Debug_House",
            "UI_SC_Debug_HouseLocation",
            "UI_SC_Debug_LocateHouse",
            "UI_SC_Debug_ClearHouseMarker",
        ):
            self.assertIn(key, translations)

    def test_debug_movement_recorder_is_selected_companion_scoped(self) -> None:
        debug = lua_function(self.ui, "function SCUIDetail:buildDebug(panel)")
        handler = lua_function(self.ui, "local function onSupportButton(target, button)")
        self.assertIn("SC.Locomotion.snapshot(selected.actor)", debug)
        self.assertIn('"movement_copy"', debug + handler)
        self.assertIn('"movement_refresh"', debug + handler)
        self.assertIn('"movement_clear"', debug + handler)
        self.assertIn("target.root.selectedRow", handler)
        translations = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        required = {
            "UI_SC_Debug_Movement", "UI_SC_Debug_MovementState",
            "UI_SC_Debug_MovementTarget", "UI_SC_Debug_MovementNative",
            "UI_SC_Debug_MovementBlocker", "UI_SC_Debug_MovementCopy",
            "UI_SC_Debug_MovementRefresh", "UI_SC_Debug_MovementClear",
        }
        self.assertFalse(required - set(translations))

    def test_faction_residents_are_isolated_from_companion_roster(self) -> None:
        roster = lua_function(self.ui, "function SCUIRoot:refreshRoster(")
        self.assertIn("row.factionMember ~= true", roster)
        self.assertIn("row.factionId == nil", roster)

    def test_faction_trade_and_restitution_are_scrollable_controls(self) -> None:
        factions = lua_function(self.ui, "function SCUIDetail:buildFactions(panel)")
        self.assertIn("SC.Trade.playerCatalog", factions)
        self.assertIn("SC.Trade.catalog", factions)
        self.assertIn("SC.Trade.canOfferRestitution", factions)
        self.assertIn('\"reconcile\", summary.id', factions)

    def test_social_contract_conversation_is_contextual_and_actionable(self) -> None:
        factions = lua_function(self.ui, "function SCUIDetail:buildFactions(panel)")
        handler = lua_function(self.ui, "local function onFactionButton(target, button)")
        self.assertIn("SC.FactionContracts.canTalk", factions)
        for action in ("talk_needs", "talk_members", "talk_trade", "talk_danger",
                       "accept_contract", "fulfill_contract", "withdraw_contract",
                       "request_access"):
            self.assertIn(f'\"{action}\"', factions + handler)
        self.assertIn("futureRecruitConsideration", factions)

    def test_faction_recruitment_exposes_candidate_trial_and_decision_controls(self) -> None:
        factions = lua_function(self.ui, "function SCUIDetail:buildFactions(panel)")
        handler = lua_function(self.ui, "local function onFactionButton(target, button)")
        context = lua_function(self.context,
                               "local function addFactionConversations(context, factions, player)")
        for action in ("recruitment_ask", "recruitment_trial",
                       "recruitment_decide", "recruitment_return"):
            self.assertIn(f'"{action}"', factions + handler + context)
        self.assertIn("recruitment.canStartTrial", factions)
        self.assertIn("recruitment.canDecide", factions)
        translations = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        required = {
            "UI_SC_Faction_Recruitment", "UI_SC_Faction_RecruitmentCandidate",
            "UI_SC_Faction_RecruitmentStartTrial", "UI_SC_Faction_RecruitmentAskDecision",
            "UI_SC_Debug_RecruitmentJoin", "IGUI_SC_FactionRecruit_Join",
        }
        self.assertFalse(required - set(translations))

    def test_minimap_overlay_only_reads_recruited_registry_records(self) -> None:
        source = read(CLIENT / "SCCompanionMap.lua")
        self.assertIn('record.recruited == true', source)
        self.assertIn('worldToUIX', source)
        self.assertIn('worldToUIY', source)
        self.assertIn('identity.forename', source)
        self.assertIn('map:drawRect', source)
        self.assertIn('map:drawText', source)
        self.assertNotIn('record.factionId ==', source)
        self.assertIn('ISMiniMapInner.render = renderWrapper', source)

    def test_social_contract_hardening_is_visible_and_confirmed(self) -> None:
        factions = lua_function(self.ui, "function SCUIDetail:buildFactions(panel)")
        handler = lua_function(self.ui, "local function onFactionButton(target, button)")
        for token in (
            "social.progress", "progress.requirements", "hoursRemaining",
            "UI_SC_Faction_ThreatProgress", "UI_SC_Faction_DeliveryProgress",
            "contract.marker", "social.notifications", "social.reserveSummary",
            "SC.FactionContracts.safeRestStatus",
        ):
            self.assertIn(token, factions)
        self.assertNotIn("deadlineHour) or 0", factions)
        self.assertIn("pendingContractWithdraw", handler)
        self.assertIn("now + 8000", handler)
        self.assertIn("UI_SC_Faction_WithdrawConfirm", handler)

    def test_contract_ui_uses_english_translation_keys_for_all_new_status_text(self) -> None:
        translations = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        required = {
            "UI_SC_Faction_SafeRestGranted", "UI_SC_Faction_SafeRestDenied",
            "UI_SC_Faction_SafeRestReady", "UI_SC_Faction_SafeRestBlocked",
            "UI_SC_Faction_DeadlineValue", "UI_SC_Faction_DeliveryProgress",
            "UI_SC_Faction_ThreatProgress", "UI_SC_Faction_MapMarkerActive",
            "UI_SC_Faction_MapMarkerPending", "UI_SC_Faction_LatestUpdate",
            "UI_SC_Faction_ReserveAll", "UI_SC_Faction_ReserveCount",
        }
        self.assertFalse(required - set(translations))
        for key in required:
            self.assertTrue(translations[key].strip(), key)

    def test_household_entrance_context_opens_real_conversation(self) -> None:
        finder = lua_function(self.context, "local function talkableFactions(player)")
        builder = lua_function(self.context, "local function addFactionConversations(context, factions, player)")
        self.assertIn("SC.FactionContracts.canTalk", finder)
        self.assertIn('SC.UI.open(\"factions\")', self.context)
        for topic in ("status", "needs", "members", "trade", "danger", "rumours"):
            self.assertIn(f'topic = \"{topic}\"', builder)
        self.assertIn('group.id, \"access\"', builder)

    def test_detail_scroll_is_instantiated_in_b42_order(self) -> None:
        block = lua_function(self.ui, "function SCUIDetail:rebuild(preserveScroll)")
        instantiate = block.index("panel:instantiate()")
        scroll_children = block.index("panel:setScrollChildren(true)")
        scroll_bars = block.index("panel:addScrollBars(false)")
        self.assertLess(instantiate, scroll_children)
        self.assertLess(scroll_children, scroll_bars)
        self.assertIn("panel:setScrollHeight(contentHeight)", block)
        self.assertIn("panel:setScrollWidth(contentWidth)", block)
        self.assertIn("contentHeight - panel:getHeight()", block)
        self.assertIn("Bounds.clamp(previousY, -maximumScroll, 0)", block)

    def test_detail_content_is_stencilled_and_vertical_only(self) -> None:
        prerender = lua_function(self.ui, "function SCUIClippedScrollPanel:prerender()")
        render = lua_function(self.ui, "function SCUIClippedScrollPanel:render()")
        self.assertIn("self:setStencilRect(0, 0, self:getWidth(), self:getHeight())", prerender)
        self.assertIn("self:clearStencilRect()", render)
        self.assertIn("self:repaintStencilRect", render)
        self.assertNotIn("panel:addScrollBars(true)", self.ui)

    def test_detail_buttons_never_expand_past_the_viewport(self) -> None:
        for marker in (
            "function SCUIDetail:addCommand(panel, y, labelKey, command, payload)",
            "function SCUIDetail:addSignal(panel, y, labelKey, signal)",
        ):
            block = lua_function(self.ui, marker)
            self.assertIn("local buttonWidth = availableWidth", block)
            self.assertIn("local visibleLabel = fitText", block)
            self.assertNotIn("UI.textWidth(UIFont.Small, fullLabel) + 20", block)
        command = lua_function(
            self.ui,
            "function SCUIDetail:addCommand(panel, y, labelKey, command, payload)",
        )
        self.assertIn("local visibleLabel = fitText", command)
        self.assertIn("math.max(40, buttonWidth - 16)", command)
        self.assertIn("button.scLabel = fullLabel", command)
        crisis = lua_function(
            self.ui,
            "function SCUIDetail:addCrisisAction(panel, y, labelKey, crisisId, outcome, action)",
        )
        self.assertIn("math.max(100, panel:getWidth() - 28)", crisis)
        self.assertIn("local visibleLabel = fitText", crisis)
        autonomy = lua_function(
            self.ui,
            "function SCUIDetail:addAutonomyAction(panel, y, labelKey, choice)",
        )
        self.assertIn("math.max(100, panel:getWidth() - 28)", autonomy)
        self.assertIn("local visibleLabel = fitText", autonomy)

    def test_carry_policy_labels_are_compact(self) -> None:
        en_data = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        self.assertEqual(en_data["UI_SC_Action_AllowOverload"], "Allow overload")
        self.assertEqual(en_data["UI_SC_Action_DisallowOverload"], "Prevent overload")

    def test_living_survivor_state_and_requests_are_visible(self) -> None:
        for field in (
            "stressResponseLabel", "joyResponseLabel", "boredom", "topThoughts",
            "currentExpectation", "activeEpisode", "inspiration", "pendingRequest",
        ):
            self.assertIn(field, self.ui)
        self.assertIn("function SCUIDetail:addAutonomyAction", self.ui)
        self.assertIn("SC.Autonomy.respond", self.ui)
        self.assertIn('row.pendingRequest.kind == "supply_run"', self.ui)

    def test_full_menu_surfaces_remain_translucent(self) -> None:
        self.assertIn("local function makeButtonTranslucent(button)", self.ui)
        self.assertIn("local function configuredOpacity", self.ui)
        self.assertIn('SC.Config.get("uiPanelOpacity")', self.ui)
        self.assertIn("a = configuredOpacity(0.58, 0.18, 0.72)", self.ui)
        self.assertIn("a = configuredOpacity(1, 0.25, 0.85)", self.ui)
        self.assertNotIn("a = 0.94", self.ui)

    def test_all_required_commands_are_routed(self) -> None:
        required = {
            "status",
            "memory",
            "recruit",
            "dismiss",
            "follow",
            "stay",
            "guard",
            "regroup",
            "retreat",
            "set_follow_distance",
            "set_scavenge",
            "set_ride_with_player",
            "set_allow_overload",
            "set_work_mode",
            "set_move_mode",
            "set_combat_doctrine",
            "set_weapon_priority",
            "move_to",
            "open_door",
            "close_door",
            "check_room",
            "barricade",
            "remove_barricade",
            "dismantle",
            "open_inventory",
            "open_health",
        }
        command_literals = set(
            re.findall(
                r'(?:add(?:Boolean)?Command\([^\n]*?|button\.scCommand\s*=\s*)\"([a-z_]+)\"',
                self.ui + "\n" + self.context,
            )
        )
        command_literals.update(
            re.findall(
                r'addBooleanCommand\([^,]+,[^,]+,[^,]+,\s*\"([a-z_]+)\"',
                self.ui,
            )
        )
        command_literals.update(re.findall(r'scCommand\s*=\s*\"([a-z_]+)\"', self.ui))
        command_literals.update(re.findall(r'\"(set_[a-z_]+)\"', self.ui))
        self.assertFalse(required - command_literals, f"missing commands: {sorted(required - command_literals)}")
        self.assertIn("pcall(SC.Commands.issue", self.ui)
        self.assertIn("pcall(SC.Commands.issue, companionId, command, payload, player)", self.context)

    def test_command_buttons_use_local_preflight_reasons(self) -> None:
        block = lua_function(self.ui, "function UI.commandAvailability(row, command, payload)")
        for key in (
            "UI_SC_Disabled_NoSelection",
            "UI_SC_Disabled_NotAlive",
            "UI_SC_Disabled_Unavailable",
            "UI_SC_Disabled_AlreadyRecruited",
            "UI_SC_Disabled_RecruitedOnly",
            "UI_SC_Disabled_TooFar",
            "UI_SC_Disabled_NoGroup",
        ):
            self.assertIn(key, block)
        self.assertNotIn("pcall(SC.Commands.issue", block)
        self.assertNotIn("canIssue", block)
        self.assertIn("if reasonArgument ~= nil then", self.ui)
        self.assertIn("button.tooltip = UI.text(reasonKey, reasonArgument)", self.ui)
        self.assertIn("button.tooltip = UI.text(reasonKey)", self.ui)

    def test_remove_from_group_uses_empty_backend_value(self) -> None:
        self.assertIn('{ id = "", key = "UI_SC_Select_GroupNone" }', self.ui)
        groups = lua_function(self.ui, "function SCUIDetail:buildGroups(panel, row)")
        self.assertIn('GROUPS, "set_group", "group"', groups)
        self.assertNotIn('{ group = "none" }', self.ui)

    def test_door_payload_uses_the_live_door_square(self) -> None:
        self.assertIn('doorPayload = squarePayload(safeMethod(door, "getSquare"))', self.context)
        self.assertIn("doorPayload.object = door", self.context)
        self.assertIn('doorPayload.objectIndex = safeMethod(door, "getObjectIndex")', self.context)
        self.assertIn('"open_door", doorPayload', self.context)
        self.assertIn('"close_door", doorPayload', self.context)

    def test_barricade_payload_keeps_only_a_live_object_and_stable_index(self) -> None:
        self.assertIn('barricadePayload = squarePayload(safeMethod(barricadeTarget, "getSquare"))',
                      self.context)
        self.assertIn("barricadePayload.object = barricadeTarget", self.context)
        self.assertIn('barricadePayload.objectIndex = safeMethod(barricadeTarget, "getObjectIndex")',
                      self.context)
        self.assertIn('"barricade", barricadePayload', self.context)

    def test_context_commands_are_grouped_and_targeted_work_uses_live_objects(self) -> None:
        for key in (
            "UI_SC_Context_Talk",
            "UI_SC_Context_Orders",
            "UI_SC_Context_TargetActions",
            "UI_SC_Context_Companion",
        ):
            self.assertIn(f'addCategory(companionMenu, "{key}")', self.context)
        self.assertIn('removeBarricadePayload.object = removeBarricadeTarget', self.context)
        self.assertIn('dismantlePayload.object = dismantleTarget', self.context)
        self.assertIn('"remove_barricade", removeBarricadePayload', self.context)
        self.assertIn('"dismantle", dismantlePayload', self.context)
        self.assertIn('removeBarricadePayload.barricadeSide', self.context)

    def test_status_open_and_scheduler_contracts_are_exposed(self) -> None:
        self.assertIn("function UI.open(tab, companionId, description)", self.ui)
        self.assertIn("root:setCollapsed(false)", self.ui)
        self.assertIn("root:refreshRoster(companionId or descriptionId, description, true)", self.ui)
        self.assertIn("function UI.showStatus(description)", self.ui)
        self.assertIn('return UI.open("status", companionId, description)', self.ui)
        self.assertIn("function UI.isOpen()", self.ui)
        scheduled = lua_function(self.ui, "function UI.scheduledRefresh()")
        self.assertIn("if not UI.isOpen()", scheduled)
        self.assertIn("isUserInteracting()", scheduled)
        self.assertIn("refreshPending = true", scheduled)
        self.assertIn("refreshRoster(nil, nil, true)", scheduled)

    def test_periodic_refresh_never_replaces_a_captured_scrollbar(self) -> None:
        interaction = lua_function(self.ui, "function SCUIRoot:isUserInteracting()")
        self.assertIn("rosterBar.scrolling == true", interaction)
        self.assertIn("detailBar.scrolling == true", interaction)
        self.assertIn('safeMethod(rosterBar, "getIsCaptured")', interaction)
        self.assertIn('safeMethod(detailBar, "getIsCaptured")', interaction)
        self.assertIn("child.expanded == true", interaction)

    def test_command_selectors_do_not_depend_on_kahlua_global_next(self) -> None:
        selector = lua_function(self.ui, "function SCUIDetail:addCommandSelector(")
        change = lua_function(self.ui, "local function onCommandSelector(target, combo)")
        self.assertIn("tableHasEntries(availabilityPayload)", selector)
        self.assertIn("tableHasEntries(payload)", change)
        self.assertNotIn("next(", selector + change)

    def test_roster_extent_is_reset_and_scroll_is_clamped(self) -> None:
        block = lua_function(self.ui, "function SCUIRoot:refreshRoster(preferredId, description, preserveScroll)")
        clear_index = block.index("self.roster:clear()")
        reset_positions = [match.start() for match in re.finditer(r"self\.roster:setScrollHeight\(0\)", block)]
        self.assertGreaterEqual(len(reset_positions), 2)
        self.assertLess(reset_positions[0], clear_index)
        self.assertGreater(reset_positions[-1], clear_index)
        self.assertIn("self.roster:setScrollHeight(contentHeight)", block)
        self.assertIn("Bounds.clamp(desiredScroll, -maximumScroll, 0)", block)

    def test_saved_tab_is_applied_to_detail_on_creation(self) -> None:
        create = lua_function(self.ui, "function SCUIRoot:createChildren()")
        self.assertIn("self.detail:setTab(self.selectedTab)", create)

    def test_formatters_match_actual_describe_shapes(self) -> None:
        runtime_test = read(PROJECT / "tests" / "ui" / "SCUIFormatTests.lua")
        for field in (
            "name",
            "bleeding",
            "bitten",
            "infected",
            "bandaged",
            "dirtyBandage",
            "scratched",
            "cut",
            "deepWound",
            "burned",
            "fractured",
            "severity",
        ):
            self.assertRegex(runtime_test, rf"\b{field}\s*=")
        self.assertIn("supplies = { bandages = 3, food = 2, water = 4, ammunition = 37 }", runtime_test)
        self.assertIn('knox = "No Knox symptoms observed"', runtime_test)
        self.assertIn('Format.stateText("very_careful", text) == "Very careful"', runtime_test)
        self.assertIn("UI.formatWounds(row.wounds)", self.ui)
        self.assertIn("UI.formatSupplies(row.supplies)", self.ui)
        self.assertIn("UI.formatKnox(row.knox)", self.ui)

    def test_inventory_and_health_bridges_are_truthful(self) -> None:
        self.assertIn("function UI.openInventory(actor, player)", self.ui)
        self.assertIn("function UI.openHealth(actor, player)", self.ui)
        self.assertIn("lootPage:setNewContainer(inventory)", self.bridge)
        self.assertIn("lootPage:setVisible(true)", self.bridge)
        self.assertIn("lootPage.isCollapsed = false", self.bridge)
        self.assertIn('pcall(openFunction, "loadout", id, description)', self.bridge)
        self.assertIn('root.detail.tab == "loadout"', self.bridge)
        self.assertIn("root.detail.displayedCompanionId == id", self.bridge)
        health = lua_function(self.ui, "function SCUIDetail:buildLoadout(panel, row)")
        self.assertIn("UI.formatWounds(row.wounds)", health)
        self.assertIn("UI.formatKnox(row.knox)", health)
        mock_test = read(PROJECT / "tests" / "ui" / "SCUIBridgeTests.lua")
        self.assertIn("Bridge.openInventory(actor, player)", mock_test)
        self.assertIn("Bridge.openHealth(actor, player", mock_test)
        self.assertIn("noOpHealth == false", mock_test)

    def test_tab_names_are_case_normalized(self) -> None:
        normalize = lua_function(self.ui, "function UI.normalizeTab(tab)")
        self.assertIn("string.lower(tab)", normalize)
        self.assertIn("local requestedTab = UI.normalizeTab(tab)", self.ui)
        self.assertIn("self.selectedTab = UI.normalizeTab(tab)", self.ui)

    def test_player_signals_are_accessible_and_truthful(self) -> None:
        availability = lua_function(self.ui, "function UI.signalAvailability(root, signal, activePlayer)")
        self.assertIn('type(SC.Commands.whistle) ~= "function"', availability)
        self.assertIn('type(SC.Commands.handSign) ~= "function"', availability)
        self.assertIn('safeMethod(actor, "CanSee", player)', availability)
        self.assertIn('return false, "UI_SC_Disabled_NoVisibleRecruits"', availability)
        self.assertIn("if uncertain then", availability)
        callback = lua_function(self.ui, "local function onSignalButton(target, button)")
        self.assertIn("local player = playerForUI()", callback)
        self.assertIn("UI.signalAvailability(target.root, button.scSignal, player)", callback)
        self.assertIn("pcall(SC.Commands.whistle, player)", callback)
        self.assertIn("pcall(SC.Commands.handSign, player, button.scSignal)", callback)
        self.assertIn("UI.signalSuccessText(reason, extra)", callback)
        overview = lua_function(self.ui, "function SCUIDetail:buildStatus(panel, row)")
        for signal in (
            "whistle", "follow", "hold", "regroup", "cautious", "move_out",
            "cease_fire", "fire", "fall_back",
        ):
            self.assertIn(f'"{signal}"', overview)
        self.assertLess(overview.index("UI_SC_Section_Signals"), overview.index("UI_SC_Section_Conversation"))

    def test_relationship_conversation_and_emotes_are_exposed(self) -> None:
        overview = lua_function(self.ui, "function SCUIDetail:buildStatus(panel, row)")
        for command in (
            "status", "needs", "memory", "background", "opinion", "relationship",
            "encourage", "praise", "plans", "recruit", "dismiss",
        ):
            self.assertIn(f'"{command}"', overview)
        for emote in ("wavehi", "signalok", "thankyou", "clap", "salute", "shrug"):
            self.assertIn(f'emote = "{emote}"', overview)
        for key in (
            "UI_SC_Info_Bond", "UI_SC_Info_Mood", "UI_SC_Info_Morale", "UI_SC_Info_Stress",
            "UI_SC_Info_Relationship", "UI_SC_Info_CurrentNeed", "UI_SC_Info_TimeTogether",
            "UI_SC_Info_RecentMemory", "UI_SC_Info_Background",
        ):
            self.assertIn(key, overview)
        self.assertLess(overview.index("UI_SC_Section_Conversation"), overview.index("UI_SC_Section_Emotes"))
        conversation = lua_function(self.context, "local function addConversation(menu, row, player)")
        for command in ("needs", "background", "opinion", "plans", "relationship", "encourage", "praise", "emote"):
            self.assertIn(f'"{command}"', conversation)
        self.assertIn("if row.recruited ~= true then return end", conversation)

    def test_recruitment_is_primary_and_hides_after_joining(self) -> None:
        overview = lua_function(self.ui, "function SCUIDetail:buildStatus(panel, row)")
        self.assertIn("row.recruited ~= true", overview)
        self.assertIn("row.recruited == true", overview)
        self.assertLess(overview.index('"recruit"'), overview.index("UI_SC_Section_Status"))
        self.assertGreater(overview.index('"dismiss"'), overview.index("UI_SC_Section_Conversation"))
        context = lua_function(self.context, "local function addConversation(menu, row, player)")
        self.assertIn("if row.recruited ~= true then return end", context)
        self.assertNotIn('"recruit"', context)

    def test_world_companion_commands_only_list_recruited_team_members(self) -> None:
        nearby = lua_function(self.context, "local function nearbyRows(player)")
        self.assertIn('type(SC.Registry.byId) == "function"', nearby)
        self.assertIn("record.actor == entry and record.recruited == true", nearby)
        self.assertIn("if recruited and row", nearby)
        fill = lua_function(
            self.context,
            "function Context.fillWorldObjectContextMenu(playerIndex, context, worldObjects, test)",
        )
        self.assertIn("if row.recruited == true then", fill)

    def test_stable_roster_refresh_avoids_full_rebuild_flicker(self) -> None:
        refresh = lua_function(self.ui, "function SCUIRoot:refreshRoster(preferredId, description, preserveScroll)")
        self.assertIn("local canReuse = #entries == #(self.roster.items or {})", refresh)
        self.assertIn("item.item = row", refresh)
        self.assertIn("local signature = detailRowSignature(self.selectedRow)", refresh)
        self.assertLess(refresh.index("if canReuse then"), refresh.index("self.roster:clear()"))

    def test_companion_names_prefer_survivor_identity_over_player_display_name(self) -> None:
        gameplay = read(CLIENT / "SCGameplayUtil.lua")
        name_of = lua_function(gameplay, "function U.nameOf(actor)")
        self.assertLess(name_of.index('U.call(actor, "getDescriptor")'),
                        name_of.index('U.call(actor, "getDisplayName")'))

    def test_journal_is_read_only_and_bounded(self) -> None:
        journal = read(CLIENT / "SCJournal.lua")
        self.assertIn("function Journal.build(actor, state, description)", journal)
        self.assertIn('U().config("maxJournalMemories") or 12', journal)
        for mutator in ("Objectives.initialize", "Objectives.update", "respondPlans", "writeStable"):
            self.assertNotIn(mutator, journal)
        build = lua_function(self.ui, "function SCUIDetail:buildJournal(panel, row)")
        for section in (
            "UI_SC_Journal_Who", "UI_SC_Journal_Relationship", "UI_SC_Journal_Goal",
            "UI_SC_Journal_Keepsake", "UI_SC_Journal_Memories", "UI_SC_Journal_SharedLife",
        ):
            self.assertIn(section, build)
        for field in ("UI_SC_Journal_Profession", "UI_SC_Journal_Aptitude",
                      "UI_SC_Journal_PreferredRole"):
            self.assertIn(field, build)

    def test_grief_is_visible_in_status_journal_and_household_ui(self) -> None:
        overview = lua_function(self.ui, "function SCUIDetail:buildStatus(panel, row)")
        factions = lua_function(self.ui, "function SCUIDetail:buildFactions(panel)")
        commands = read(CLIENT / "SCCommands.lua")
        relationship = read(CLIENT / "SCRelationship.lua")
        community = read(CLIENT / "SCCommunity.lua")
        runtime = read(CLIENT / "SCRuntime.lua")
        for token in ("UI_SC_Info_Grief", "UI_SC_Info_GriefValue"):
            self.assertIn(token, overview)
        self.assertIn("UI_SC_Faction_Mourning", factions)
        self.assertIn("autonomy.grief", commands)
        self.assertIn("IGUI_SC_Status_Grieving", relationship)
        self.assertIn("IGUI_SC_Memory_CompanionDied", relationship)
        self.assertIn("function Community.noteCompanionDeath(record)", community)
        self.assertIn("function Community.activeGrief(actorOrId)", community)
        self.assertIn("SC.Community.noteCompanionDeath", runtime)
        translations = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        required = {
            "UI_SC_Info_Grief", "UI_SC_Info_GriefValue",
            "UI_SC_Faction_Mourning", "UI_SC_Faction_MourningValue",
            "IGUI_SC_Status_Grieving", "IGUI_SC_Memory_CompanionDied",
        }
        self.assertFalse(required - set(translations))

    def test_move_mode_payloads_match_the_backend_contract(self) -> None:
        orders = lua_function(self.ui, "function SCUIDetail:buildOrders(panel)")
        self.assertIn('MOVE_MODES, "set_move_mode", "mode"', orders)
        for mode in ("copy", "walk", "sneak", "jog"):
            self.assertIn(f'{{ id = "{mode}", key = "UI_SC_Select_Move', self.ui)
        self.assertIn('row and row.moveMode or "copy"', orders)
        self.assertEqual(self.translations["UI_SC_Select_MoveCopyPlayer"], "Copy player")
        self.assertIn("crouch, walk, and run",
                      self.translations["UI_SC_Action_MoveCopyPlayer"])
        self.assertNotIn('{ id = "run",', self.ui)

    def test_scavenging_is_one_stateful_checkbox(self) -> None:
        orders = lua_function(self.ui, "function SCUIDetail:buildOrders(panel)")
        self.assertIn('self:addBooleanCommand(panel, y, "UI_SC_Toggle_Scavenging"', orders)
        self.assertIn('"set_scavenge", "scavenge", row and row.scavenge == true', orders)
        self.assertNotIn("UI_SC_Action_ScavengeOn", self.ui)
        self.assertNotIn("UI_SC_Action_ScavengeOff", self.ui)
        toggle = lua_function(
            self.ui,
            "function SCUIDetail:addBooleanCommand(panel, y, labelKey, command, rowField, selected)",
        )
        self.assertIn("ISTickBox:new", toggle)
        self.assertIn("tickBox:setSelected(1, selected == true)", toggle)
        callback = lua_function(self.ui, "local function onBooleanCommand(target, index, selected, command, payloadKey, tickBox)")
        self.assertIn("payload[payloadKey] = selected == true", callback)
        self.assertIn("onCommandButton(target", callback)
        self.assertIn("tickBox:setSelected(index, previous)", callback)

    def test_supervised_action_status_and_talk_command_are_visible(self) -> None:
        overview = lua_function(self.ui, "function SCUIDetail:buildStatus(panel, row)")
        support = lua_function(self.ui, "function SCUIDetail:buildSupport(panel)")
        self.assertIn("UI_SC_Info_CurrentAction", overview)
        self.assertIn("UI_SC_Info_LastActionFailure", overview)
        self.assertIn('"UI_SC_Action_Doing", "doing"', overview)
        self.assertIn("UI_SC_Support_ActionSupervisor", support)
        self.assertIn('addCommand(menu, "UI_SC_Action_Doing"', self.context)
        for key in ("UI_SC_Action_Doing", "UI_SC_Info_CurrentAction",
                    "UI_SC_Info_LastActionFailure", "UI_SC_Support_ActionSupervisor"):
            self.assertIn(key, self.translations)

    def test_work_mode_selector_matches_the_persistent_backend_contract(self) -> None:
        orders = lua_function(self.ui, "function SCUIDetail:buildOrders(panel)")
        self.assertIn('WORK_MODES, "set_work_mode", "mode"', orders)
        for mode in ("auto", "idle", "craft"):
            self.assertIn(f'{{ id = "{mode}", key = "UI_SC_Select_Work', self.ui)
        self.assertIn("UI_SC_Info_WorkMode", self.ui)

    def test_vehicle_policy_is_one_persistent_toggle_with_manifest_status(self) -> None:
        gear = lua_function(self.ui, "function SCUIDetail:buildLoadout(panel, row)")
        self.assertIn('"set_ride_with_player", "rideWithPlayer"', gear)
        self.assertIn("row.vehicleStatus", gear)
        self.assertIn("UI_SC_Vehicle_Assigned", gear)
        self.assertIn("UI_SC_Vehicle_Waiting", gear)
        self.assertNotIn('"board_vehicle", nil', gear)
        self.assertIn('row.vehicleStatus.status == "in_vehicle"', gear)
        self.assertIn("row.vehicleStatus.canExitNow == true", gear)
        self.assertIn('"UI_SC_Action_ExitVehicleNow"', gear)
        self.assertIn('"exit_vehicle", nil', gear)
        for status in ("on_foot", "approaching_vehicle", "in_vehicle", "waiting_safe_exit"):
            self.assertIn(f'"UI_SC_VehicleStatus_{status}"', read(TRANSLATE / "EN" / "UI.json"))
        self.assertIn("UI_SC_Info_WeaponPriority", gear)
        self.assertIn("UI_SC_Info_EquippedWeapon", gear)

        groups = lua_function(self.ui, "function SCUIDetail:buildGroups(panel, row)")
        self.assertNotIn('"board_vehicle"', groups)
        self.assertNotIn('"exit_vehicle"', groups)

    def test_combat_is_one_per_companion_selector_with_apply_to_all(self) -> None:
        orders = lua_function(self.ui, "function SCUIDetail:buildOrders(panel)")
        # One per-companion combat selector (the doctrine cascades to the
        # underlying stance + hold-fire), plus an apply-to-whole-squad button.
        self.assertIn("COMBAT_DOCTRINES", orders)
        self.assertIn('"set_combat_doctrine", "doctrine"', orders)
        self.assertIn('scope = "team"', orders)
        self.assertIn("UI_SC_Action_ApplyToAll", orders)
        # The old, separate stance selector and hold-fire toggle are gone.
        self.assertNotIn("COMBAT_STANCES", orders)
        self.assertNotIn('"set_combat_mode"', orders)
        self.assertNotIn('"set_hold_fire"', orders)

    def test_compact_policy_selectors_include_backend_modes(self) -> None:
        orders = lua_function(self.ui, "function SCUIDetail:buildOrders(panel)")
        gear = lua_function(self.ui, "function SCUIDetail:buildLoadout(panel, row)")
        groups = lua_function(self.ui, "function SCUIDetail:buildGroups(panel, row)")
        self.assertIn("MAIN_ORDERS", orders)
        self.assertIn("FOLLOW_DISTANCES", orders)
        self.assertIn("COMBAT_DOCTRINES", orders)
        self.assertIn('"set_combat_doctrine", "doctrine"', orders)
        self.assertIn("WEAPON_PRIORITIES", gear)
        self.assertIn('{ id = "quiet", key = "UI_SC_Select_WeaponQuiet" }', self.ui)
        self.assertIn('"set_allow_overload", "allowOverload"', gear)
        self.assertIn("GROUPS", groups)
        self.assertNotIn("UI_SC_Action_Follow", orders)
        self.assertNotIn("UI_SC_Action_Stay", orders)
        self.assertNotIn("UI_SC_Action_Guard", orders)

    def test_every_menu_button_produces_visible_result_feedback(self) -> None:
        callback = lua_function(self.ui, "local function onCommandButton(target, button)")
        self.assertIn("setButtonFeedback(target", callback)
        self.assertIn("UI_SC_CommandAcceptedDetail", callback)
        self.assertIn("UI_SC_CommandRejectedDetail", callback)
        self.assertIn("UI_SC_Result_WeaponEquipped", callback)
        add_command = lua_function(
            self.ui,
            "function SCUIDetail:addCommand(panel, y, labelKey, command, payload)",
        )
        self.assertIn("button.scLabel = fullLabel", add_command)
        render = lua_function(self.ui, "function SCUIDetail:render()")
        self.assertIn("self.feedbackUntil", render)
        self.assertIn("self:drawRect", render)
        self.assertIn("footerTop", render)
        self.assertIn("self:feedbackFooterHeight()", render)
        rebuild = lua_function(self.ui, "function SCUIDetail:rebuild(preserveScroll)")
        self.assertIn("self:contentViewportHeight()", rebuild)

    def test_command_feedback_has_a_reserved_non_overlapping_footer(self) -> None:
        viewport = lua_function(self.ui, "function SCUIDetail:contentViewportHeight()")
        self.assertIn("self:getHeight() - self:feedbackFooterHeight() - 2", viewport)
        layout = lua_function(self.ui, "function SCUIRoot:applyLayout()")
        self.assertIn("self.detail:contentViewportHeight()", layout)

    def test_ui_settings_are_separate_from_companion_save(self) -> None:
        self.assertIn('UI.SETTINGS_KEY = "SC_UISettings"', self.ui)
        self.assertNotIn("SC_SaveV1", self.all_source)

    def test_visibility_migration_opens_existing_and_new_saves_once(self) -> None:
        ensure = lua_function(self.ui, "function UI.ensureControl()")
        self.assertIn("settings.visibilityRevision", ensure)
        self.assertIn("settings.collapsed = false", ensure)
        self.assertIn("UI.SETTINGS_VISIBILITY_REVISION", ensure)

    def test_f7_hotkey_is_registered_and_toggles_the_menu(self) -> None:
        self.assertIn('UI.HOTKEY_ACTION = "Toggle Living Fellows menu"', self.ui)
        self.assertIn("UI.DEFAULT_HOTKEY = Keyboard.KEY_F7", self.ui)
        self.assertIn("table.insert(keyBinding", self.ui)
        hotkey = lua_function(self.ui, "function UI.onKeyPressed(key)")
        self.assertIn("UI.toggle()", hotkey)
        self.assertIn("getKey", hotkey)
        self.assertIn('self:drawTextCentre("LF"', self.ui)

    def test_saved_collapsed_launcher_is_restored_after_game_ui_startup(self) -> None:
        startup = lua_function(self.ui, "function UI.onGameStart()")
        restore = lua_function(self.ui, "function UI.restoreStartupVisibility()")
        create_player = lua_function(self.ui, "function UI.onCreatePlayer(")
        hooks = lua_function(self.ui, "function UI.installHooks()")

        self.assertIn("UI._gameStarted = true", startup)
        self.assertIn("UI.restoreStartupVisibility()", startup)
        self.assertIn("if UI._gameStarted then", create_player)
        self.assertLess(
            restore.index("UI.hideCollapsedLauncher()"),
            restore.index("UI.showCollapsedLauncher(root)"),
        )
        self.assertIn("Events.OnGameStart.Add(UI.onGameStart)", hooks)

    def test_pixel_symbols_are_code_drawn(self) -> None:
        self.assertIn("Pixels.bitmaps", self.pixels)
        self.assertIn("element:drawRect", self.pixels)
        self.assertNotRegex(self.pixels, r"\.png|\.jpg|\.dds|\.tga")

    def test_only_allowed_ui_event_hooks_are_used(self) -> None:
        hooks = set(re.findall(r"Events\.(On\w+)", self.all_source))
        self.assertEqual(
            hooks,
            {"OnCreatePlayer", "OnGameStart", "OnKeyPressed", "OnMainMenuEnter", "OnFillWorldObjectContextMenu"},
        )

    def test_english_only_translation_coverage(self) -> None:
        en_data = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        en_keys = set(en_data)
        language_directories = sorted(path.name for path in TRANSLATE.iterdir() if path.is_dir())
        self.assertEqual(language_directories, ["EN"])
        references = set(re.findall(r'\"(UI_SC_[A-Za-z0-9_]+)\"', self.all_source))
        dynamic_prefixes = {"UI_SC_State_", "UI_SC_Action_Distance", "UI_SC_VehicleStatus_"}
        references = {key for key in references if key not in dynamic_prefixes}
        self.assertFalse(references - en_keys, f"untranslated UI keys: {sorted(references - en_keys)}")
        for distance in (2, 3, 5, 8):
            self.assertIn(f"UI_SC_Action_Distance{distance}", en_keys)
        self.assertEqual(en_data["UI_SC_Value_Health"], "%1%%")
        self.assertIn("UI_SC_State_defensive", en_keys)
        self.assertIn("UI_SC_State_steady", en_keys)

    def test_frozen_gameplay_translation_keys_are_complete(self) -> None:
        en_data = json.loads(read(TRANSLATE / "EN" / "UI.json"))
        self.assertFalse(FROZEN_GAMEPLAY_KEYS - set(en_data))
        for key in FROZEN_GAMEPLAY_KEYS:
            self.assertTrue(en_data[key].strip(), key)
            self.assertNotEqual(en_data[key], key)

    def test_full_payload_literal_translation_audit(self) -> None:
        en_keys = set(json.loads(read(TRANSLATE / "EN" / "UI.json")))
        gettext_literals: set[str] = set()
        project_literals: set[str] = set()
        dynamic_patterns: set[str] = set()
        for _, source in payload_lua_sources():
            gettext_literals.update(literal_gettext_keys(source))
            project_literals.update(project_translation_literals(source))
            dynamic_patterns.update(dynamic_translation_patterns(source))
        self.assertFalse(gettext_literals - en_keys, f"EN missing literal getText keys: {sorted(gettext_literals - en_keys)}")
        complete_project_literals = project_literals - dynamic_patterns
        self.assertFalse(
            complete_project_literals - en_keys,
            f"EN missing payload translation literals: {sorted(complete_project_literals - en_keys)}",
        )

    def test_every_shipped_ui_lua_file_has_spdx(self) -> None:
        for path in CLIENT.glob("SCUI*.lua"):
            self.assertTrue(read(path).startswith("-- SPDX-License-Identifier: MIT"), path)


if __name__ == "__main__":
    unittest.main()
