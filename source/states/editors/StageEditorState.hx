package states.editors;

import haxe.Json;
import haxe.io.Path;

import flixel.FlxObject;
import flixel.addons.display.FlxGridOverlay;
import flixel.addons.ui.FlxUI;
import flixel.addons.ui.FlxUIInputText;
import flixel.addons.ui.FlxUINumericStepper;
import flixel.addons.ui.FlxUITabMenu;
import flixel.group.FlxGroup;
import flixel.ui.FlxButton;

import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
import openfl.utils.Assets as OpenFlAssets;

import backend.StageData;
import objects.Character;
import objects.HealthIcon;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

// ─────────────────────────────────────────────
//  StageEditorState
//  A mobile-friendly stage editor for Psych Engine
// ─────────────────────────────────────────────
class StageEditorState extends MusicBeatState
{
	// ── Layout constants ──────────────────────
	static inline var PANEL_W:Int  = 280;   // left panel width
	static inline var TAB_H:Int    = 36;    // tab button height
	static inline var DPAD_SIZE:Int = 100;  // d-pad area size
	static inline var MINI_H:Int   = 80;   // bottom mini-bar height

	// ── Stage / scene ─────────────────────────
	var stageList:Array<String>   = [];
	var selectedStage:String      = '';
	var stageSprites:FlxTypedGroup<FlxSprite>;  // rendered stage objects
	var selectedSprite:FlxSprite  = null;       // currently selected object

	// ── Characters ────────────────────────────
	var charList:Array<String>    = [];
	var dadName:String            = 'dad';
	var bfName:String             = 'bf';
	var gfName:String             = 'gf';
	var dadChar:Character         = null;
	var bfChar:Character          = null;
	var gfChar:Character          = null;
	var dadIcon:HealthIcon        = null;
	var bfIcon:HealthIcon         = null;
	var gfIcon:HealthIcon         = null;

	// camera offsets & positions (per character)
	var dadCamOffsetX:Float = 0;  var dadCamOffsetY:Float = 0;
	var bfCamOffsetX:Float  = 0;  var bfCamOffsetY:Float  = 0;
	var gfCamOffsetX:Float  = 0;  var gfCamOffsetY:Float  = 0;
	var dadPosX:Float = 100;      var dadPosY:Float = 200;
	var bfPosX:Float  = 700;      var bfPosY:Float  = 200;
	var gfPosX:Float  = 400;      var gfPosY:Float  = 350;

	// ── Left panel tabs ───────────────────────
	// 0 = Stage, 1 = Import, 2 = Characters
	var curMainTab:Int = 0;
	var tabBtns:Array<FlxButton> = [];
	var panelBg:FlxSprite;

	// Stage tab
	var stageScrollY:Float = 0;
	var stageScrollMax:Float = 0;
	var stageBtnList:Array<FlxButton> = [];

	// Import tab
	var importPathInput:FlxUIInputText;
	var importedSprites:Array<{name:String, spr:FlxSprite}> = [];
	var importScrollY:Float = 0;
	var importBtnList:Array<FlxButton> = [];
	var importErrorText:FlxText;

	// Character tab
	var charSubTab:Int  = -1; // -1 = selector, 0=dad, 1=bf, 2=gf
	var charSelectPanel:FlxGroup;
	var charDetailPanel:FlxGroup;

	// steppers for char tab
	var dadCamXStep:FlxUINumericStepper;  var dadCamYStep:FlxUINumericStepper;
	var bfCamXStep:FlxUINumericStepper;   var bfCamYStep:FlxUINumericStepper;
	var gfCamXStep:FlxUINumericStepper;   var gfCamYStep:FlxUINumericStepper;
	var dadPosXStep:FlxUINumericStepper;  var dadPosYStep:FlxUINumericStepper;
	var bfPosXStep:FlxUINumericStepper;   var bfPosYStep:FlxUINumericStepper;
	var gfPosXStep:FlxUINumericStepper;   var gfPosYStep:FlxUINumericStepper;

	// per-char preview sprites inside detail panel
	var charPreview:FlxSprite;

	// ── D-pad (left side, below panel) ────────
	var dpadGroup:FlxGroup;
	var dpadUp:FlxButton;
	var dpadDown:FlxButton;
	var dpadLeft:FlxButton;
	var dpadRight:FlxButton;
	var moveSpeed:Float = 4;

	// ── Mini bar (bottom center) ──────────────
	var miniBar:FlxGroup;

	// ── Camera ───────────────────────────────
	var camFollow:FlxObject;

	// ── Input helpers ────────────────────────
	private var blockTypingOn:Array<FlxUIInputText> = [];
	private var blockTypingOnStepper:Array<FlxUINumericStepper> = [];

	// ── File save ────────────────────────────
	var _file:FileReference;

	// ─────────────────────────────────────────
	override function create()
	{
		super.create();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Stage Editor", "Editing a Stage");
		#end

		// background
		var bg:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xFF1A1A2E);
		bg.scrollFactor.set();
		add(bg);

		// grid helper
		var grid:FlxSprite = FlxGridOverlay.create(32, 32, FlxG.width, FlxG.height, true, 0xFF1E1E3A, 0xFF22223A);
		grid.scrollFactor.set(0.5, 0.5);
		add(grid);

		// stage sprites group (world)
		stageSprites = new FlxTypedGroup<FlxSprite>();
		add(stageSprites);

		// camera
		camFollow = new FlxObject(FlxG.width / 2, FlxG.height / 2, 1, 1);
		add(camFollow);
		initPsychCamera().follow(camFollow, LOCKON, 0.06);

		// collect data
		loadStageList();
		loadCharList();

		// build UI (all scroll-factor 0 = HUD layer)
		buildPanelBg();
		buildTabButtons();
		buildStageTab();
		buildImportTab();
		buildCharTab();
		buildDPad();
		buildMiniBar();

		// show first tab
		switchMainTab(0);

		FlxG.mouse.visible = true;

		#if mobile
		addTouchPad("NONE", "NONE");
		#end
	}

	// ─────────────────────────────────────────
	//  DATA LOADERS
	// ─────────────────────────────────────────
	function loadStageList()
	{
		stageList = [];
		var tempMap:Map<String,Bool> = [];

		var fromTxt:Array<String> = Mods.mergeAllTextsNamed('data/stageList.txt', Paths.getSharedPath());
		for (s in fromTxt) {
			var t = s.trim();
			if (t.length > 0 && !tempMap.exists(t)) { tempMap.set(t, true); stageList.push(t); }
		}

		#if (MODS_ALLOWED && sys)
		var dirs:Array<String> = [
			Paths.mods('stages/'),
			Paths.mods(Mods.currentModDirectory + '/stages/'),
			Paths.getSharedPath('stages/')
		];
		for (mod in Mods.getGlobalMods()) dirs.push(Paths.mods(mod + '/stages/'));

		for (dir in dirs) {
			if (!FileSystem.exists(dir)) continue;
			for (file in Paths.readDirectory(dir)) {
				if (!FileSystem.isDirectory(dir + file) && file.endsWith('.json')) {
					var name = file.substr(0, file.length - 5);
					if (name.trim().length > 0 && !tempMap.exists(name)) {
						tempMap.set(name, true);
						stageList.push(name);
					}
				}
			}
		}
		#end

		if (stageList.length == 0) stageList.push('stage');
		selectedStage = stageList[0];
	}

	function loadCharList()
	{
		charList = Mods.mergeAllTextsNamed('data/characterList.txt', Paths.getSharedPath());
		if (charList.length == 0) charList = ['bf', 'dad', 'gf'];
	}

	// ─────────────────────────────────────────
	//  PANEL BACKGROUND
	// ─────────────────────────────────────────
	function buildPanelBg()
	{
		panelBg = new FlxSprite(0, 0).makeGraphic(PANEL_W, FlxG.height, 0xDD0D0D1F);
		panelBg.scrollFactor.set();
		add(panelBg);

		// vertical divider
		var div:FlxSprite = new FlxSprite(PANEL_W, 0).makeGraphic(2, FlxG.height, 0xFF5555AA);
		div.scrollFactor.set();
		add(div);
	}

	// ─────────────────────────────────────────
	//  TAB BUTTONS (top of panel)
	// ─────────────────────────────────────────
	function buildTabButtons()
	{
		var labels = ['Stage', 'Import', 'Chars'];
		var tabW    = Std.int(PANEL_W / labels.length);

		for (i in 0...labels.length) {
			var idx = i;
			var btn = new FlxButton(tabW * i, 0, labels[i], function() { switchMainTab(idx); });
			btn.setGraphicSize(tabW, TAB_H);
			btn.updateHitbox();
			btn.label.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, CENTER);
			btn.scrollFactor.set();
			add(btn);
			tabBtns.push(btn);
		}
	}

	function switchMainTab(tab:Int)
	{
		curMainTab = tab;

		// color active tab
		for (i in 0...tabBtns.length) {
			tabBtns[i].color = (i == tab) ? 0xFF5555FF : 0xFF333355;
		}

		// toggle visibility
		for (btn in stageBtnList)    btn.visible = (tab == 0);
		if (importPathInput != null) importPathInput.visible = (tab == 1);
		if (importErrorText != null) importErrorText.visible = (tab == 1);
		for (btn in importBtnList)   btn.visible = (tab == 1);
		charSelectPanel.visible  = (tab == 2 && charSubTab == -1);
		charDetailPanel.visible  = (tab == 2 && charSubTab >= 0);
	}

	// ─────────────────────────────────────────
	//  TAB 0 – STAGE
	// ─────────────────────────────────────────
	function buildStageTab()
	{
		var startY = TAB_H + 8;
		var btnH   = 44;
		var pad    = 4;

		for (i in 0...stageList.length) {
			var idx   = i;
			var stage = stageList[i];
			var btn   = new FlxButton(pad, startY + i * (btnH + pad), stage, function() {
				selectStage(stageList[idx]);
			});
			btn.setGraphicSize(PANEL_W - pad * 2, btnH);
			btn.updateHitbox();
			btn.label.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.WHITE, CENTER);
			btn.scrollFactor.set();
			btn.visible = false;
			add(btn);
			stageBtnList.push(btn);
		}

		stageScrollMax = Math.max(0, stageList.length * (btnH + pad) - (FlxG.height - startY - DPAD_SIZE - MINI_H - 20));
	}

	function selectStage(name:String)
	{
		selectedStage = name;
		// highlight
		for (i in 0...stageList.length) {
			stageBtnList[i].color = (stageList[i] == name) ? 0xFF5588FF : 0xFF224466;
		}
		loadStageObjects(name);
	}

	function loadStageObjects(name:String)
	{
		stageSprites.clear();
		// Load stage via StageData if available, otherwise placeholder
		try {
			var data:StageFile = StageData.getStageFile(name);
			if (data == null) throw 'No data';
			// We'll show a placeholder label since we can't render full stage here safely
			var label:FlxText = new FlxText(PANEL_W + 20, 20, 0, 'Stage: $name\n(select an object with the d-pad)', 18);
			label.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE);
			add(label);
		} catch(e) {
			var errLabel:FlxText = new FlxText(PANEL_W + 20, 20, 0, 'Could not load stage: $name', 16);
			errLabel.color = FlxColor.RED;
			add(errLabel);
		}
	}

	// ─────────────────────────────────────────
	//  TAB 1 – IMPORT
	// ─────────────────────────────────────────
	function buildImportTab()
	{
		var startY = TAB_H + 12;
		var pad    = 8;

		// path input
		var pathLabel = new FlxText(pad, startY, PANEL_W - pad * 2, 'Image path (inside images/):', 13);
		pathLabel.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.CYAN);
		pathLabel.scrollFactor.set();
		pathLabel.visible = false;
		add(pathLabel);

		importPathInput = new FlxUIInputText(pad, startY + 20, PANEL_W - pad * 2, 'MyFolder/MySprite', 12);
		importPathInput.scrollFactor.set();
		importPathInput.visible = false;
		blockTypingOn.push(importPathInput);
		add(importPathInput);

		var importBtn = new FlxButton(pad, startY + 52, 'Import', function() { doImport(); });
		importBtn.setGraphicSize(PANEL_W - pad * 2, 36);
		importBtn.updateHitbox();
		importBtn.label.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.WHITE, CENTER);
		importBtn.color = 0xFF226622;
		importBtn.scrollFactor.set();
		importBtn.visible = false;
		add(importBtn);
		importBtnList.push(importBtn);

		importErrorText = new FlxText(pad, startY + 96, PANEL_W - pad * 2, '', 12);
		importErrorText.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.RED);
		importErrorText.scrollFactor.set();
		importErrorText.visible = false;
		add(importErrorText);
	}

	function doImport()
	{
		importErrorText.text = '';
		var raw:String = importPathInput.text.trim();
		if (raw.length == 0) {
			importErrorText.text = 'Error: Please enter an image path.';
			return;
		}

		// Try loading
		var imgKey:String = 'assets/images/$raw.png';
		var exists:Bool = false;

		#if sys
		exists = FileSystem.exists(imgKey)
			|| FileSystem.exists('assets/images/$raw.xml')
			|| OpenFlAssets.exists(imgKey);
		#else
		exists = OpenFlAssets.exists(imgKey);
		#end

		if (!exists) {
			// Diagnose what's missing
			var folder = raw.indexOf('/') >= 0 ? raw.substr(0, raw.lastIndexOf('/')) : '';
			var folderExists:Bool = false;
			#if sys
			folderExists = (folder.length == 0) || FileSystem.exists('assets/images/$folder');
			#end

			if (folder.length > 0 && !folderExists)
				importErrorText.text = 'Error: Folder not found:\nimages/$folder/';
			else
				importErrorText.text = 'Error: Image not found:\nimages/$raw.png';
			return;
		}

		// Success – add sprite to world and scroll list
		var spr:FlxSprite = new FlxSprite(PANEL_W + 100, 100).loadGraphic(Paths.image(raw));
		spr.antialiasing = ClientPrefs.data.antialiasing;
		stageSprites.add(spr);
		importedSprites.push({name: raw, spr: spr});

		rebuildImportScrollList();
		importErrorText.color = FlxColor.GREEN;
		importErrorText.text  = 'Imported: $raw';
	}

	function rebuildImportScrollList()
	{
		// Remove old sprite buttons
		for (btn in importBtnList) {
			if (importBtnList.indexOf(btn) > 0) { remove(btn); btn.destroy(); }
		}
		importBtnList = [importBtnList[0]]; // keep the Import button

		var startY = TAB_H + 120;
		var btnH   = 50;
		var pad    = 6;

		for (i in 0...importedSprites.length) {
			var idx = i;
			var entry = importedSprites[i];

			var btn = new FlxButton(pad, startY + i * (btnH + pad), entry.name, function() {
				selectSprite(importedSprites[idx].spr);
			});
			btn.setGraphicSize(PANEL_W - pad * 2, btnH);
			btn.updateHitbox();
			btn.label.setFormat(Paths.font('vcr.ttf'), 11, FlxColor.WHITE, CENTER);
			btn.color = 0xFF334455;
			btn.scrollFactor.set();
			btn.visible = (curMainTab == 1);
			add(btn);
			importBtnList.push(btn);
		}
	}

	function selectSprite(spr:FlxSprite)
	{
		selectedSprite = spr;
		// highlight: tint the rest
		stageSprites.forEach(function(s:FlxSprite) {
			s.color = (s == spr) ? FlxColor.WHITE : 0xFFAAAAAA;
		});
	}

	// ─────────────────────────────────────────
	//  TAB 2 – CHARACTERS
	// ─────────────────────────────────────────
	function buildCharTab()
	{
		charSelectPanel = new FlxGroup();
		charDetailPanel = new FlxGroup();
		add(charSelectPanel);
		add(charDetailPanel);

		buildCharSelectPanel();
		buildCharDetailPanel();

		charSelectPanel.visible = false;
		charDetailPanel.visible = false;
	}

	function buildCharSelectPanel()
	{
		var pad  = 8;
		var startY = TAB_H + 10;
		var slotH  = 90;

		var chars = [
			{label:'Opponent (Dad)', ref:() -> dadName, setter: (s:String) -> { dadName = s; refreshCharPreviews(); }},
			{label:'Girlfriend (GF)', ref:() -> gfName,  setter: (s:String) -> { gfName  = s; refreshCharPreviews(); }},
			{label:'Boyfriend (BF)', ref:() -> bfName,  setter: (s:String) -> { bfName  = s; refreshCharPreviews(); }},
		];

		for (ci in 0...chars.length) {
			var c    = chars[ci];
			var idx  = ci;
			var baseY = startY + ci * (slotH + pad);

			// label
			var lbl = new FlxText(pad, baseY, PANEL_W - pad * 2, c.label, 13);
			lbl.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.CYAN);
			lbl.scrollFactor.set();
			charSelectPanel.add(lbl);

			// prev / next buttons + name text
			var nameTxt = new FlxText(pad + 36, baseY + 16, PANEL_W - pad * 2 - 72, c.ref(), 13);
			nameTxt.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.WHITE, CENTER);
			nameTxt.scrollFactor.set();
			charSelectPanel.add(nameTxt);

			var curIdx = [charList.indexOf(c.ref())];
			if (curIdx[0] < 0) curIdx[0] = 0;

			var prevBtn = new FlxButton(pad, baseY + 14, '<', function() {
				curIdx[0] = (curIdx[0] - 1 + charList.length) % charList.length;
				c.setter(charList[curIdx[0]]);
				nameTxt.text = charList[curIdx[0]];
			});
			prevBtn.setGraphicSize(32, 28);
			prevBtn.updateHitbox();
			prevBtn.scrollFactor.set();
			charSelectPanel.add(prevBtn);

			var nextBtn = new FlxButton(PANEL_W - pad - 32, baseY + 14, '>', function() {
				curIdx[0] = (curIdx[0] + 1) % charList.length;
				c.setter(charList[curIdx[0]]);
				nameTxt.text = charList[curIdx[0]];
			});
			nextBtn.setGraphicSize(32, 28);
			nextBtn.updateHitbox();
			nextBtn.scrollFactor.set();
			charSelectPanel.add(nextBtn);

			// "Open tab" button
			var openBtn = new FlxButton(pad, baseY + 48, 'Edit ' + c.label, function() { openCharSubTab(idx); });
			openBtn.setGraphicSize(PANEL_W - pad * 2, 30);
			openBtn.updateHitbox();
			openBtn.label.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, CENTER);
			openBtn.color = 0xFF333388;
			openBtn.scrollFactor.set();
			charSelectPanel.add(openBtn);
		}

		// Icon previews at the bottom
		dadIcon = new HealthIcon('dad'); dadIcon.setGraphicSize(0, 50); dadIcon.scrollFactor.set(); dadIcon.x = pad; dadIcon.y = TAB_H + 295;
		bfIcon  = new HealthIcon('bf');  bfIcon.setGraphicSize(0, 50);  bfIcon.scrollFactor.set();  bfIcon.x  = pad + 70;  bfIcon.y  = TAB_H + 295;
		gfIcon  = new HealthIcon('gf');  gfIcon.setGraphicSize(0, 50);  gfIcon.scrollFactor.set();  gfIcon.x  = pad + 140; gfIcon.y  = TAB_H + 295;
		charSelectPanel.add(dadIcon);
		charSelectPanel.add(bfIcon);
		charSelectPanel.add(gfIcon);
	}

	function openCharSubTab(idx:Int)
	{
		charSubTab = idx;
		charSelectPanel.visible = false;
		charDetailPanel.visible = true;
		refreshDetailPanel();
	}

	function closeCharSubTab()
	{
		charSubTab = -1;
		charSelectPanel.visible = true;
		charDetailPanel.visible = false;
	}

	function buildCharDetailPanel()
	{
		var pad    = 8;
		var startY = TAB_H + 8;

		// Back button
		var backBtn = new FlxButton(pad, startY, '< Back', function() { closeCharSubTab(); });
		backBtn.setGraphicSize(80, 30);
		backBtn.updateHitbox();
		backBtn.label.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.WHITE, LEFT);
		backBtn.scrollFactor.set();
		charDetailPanel.add(backBtn);

		// Title
		var titleTxt = new FlxText(pad + 90, startY + 6, PANEL_W - 90 - pad, 'Character', 14);
		titleTxt.setFormat(Paths.font('vcr.ttf'), 14, FlxColor.CYAN);
		titleTxt.scrollFactor.set();
		charDetailPanel.add(titleTxt);

		// Cam Offset
		var camLabel = new FlxText(pad, startY + 44, 0, 'Camera Offset:', 13);
		camLabel.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.LIME);
		camLabel.scrollFactor.set();
		charDetailPanel.add(camLabel);

		dadCamXStep = makeStepper(pad,        startY + 60, 10, 0, -9999, 9999, 'dadCamX');
		dadCamYStep = makeStepper(pad + 90,   startY + 60, 10, 0, -9999, 9999, 'dadCamY');
		bfCamXStep  = makeStepper(pad,        startY + 60, 10, 0, -9999, 9999, 'bfCamX');
		bfCamYStep  = makeStepper(pad + 90,   startY + 60, 10, 0, -9999, 9999, 'bfCamY');
		gfCamXStep  = makeStepper(pad,        startY + 60, 10, 0, -9999, 9999, 'gfCamX');
		gfCamYStep  = makeStepper(pad + 90,   startY + 60, 10, 0, -9999, 9999, 'gfCamY');

		charDetailPanel.add(dadCamXStep); charDetailPanel.add(dadCamYStep);
		charDetailPanel.add(bfCamXStep);  charDetailPanel.add(bfCamYStep);
		charDetailPanel.add(gfCamXStep);  charDetailPanel.add(gfCamYStep);

		// Position
		var posLabel = new FlxText(pad, startY + 100, 0, 'Position:', 13);
		posLabel.setFormat(Paths.font('vcr.ttf'), 13, FlxColor.LIME);
		posLabel.scrollFactor.set();
		charDetailPanel.add(posLabel);

		dadPosXStep = makeStepper(pad,        startY + 116, 10, 0, -9999, 9999, 'dadPosX');
		dadPosYStep = makeStepper(pad + 90,   startY + 116, 10, 0, -9999, 9999, 'dadPosY');
		bfPosXStep  = makeStepper(pad,        startY + 116, 10, 0, -9999, 9999, 'bfPosX');
		bfPosYStep  = makeStepper(pad + 90,   startY + 116, 10, 0, -9999, 9999, 'bfPosY');
		gfPosXStep  = makeStepper(pad,        startY + 116, 10, 0, -9999, 9999, 'gfPosX');
		gfPosYStep  = makeStepper(pad + 90,   startY + 116, 10, 0, -9999, 9999, 'gfPosY');

		charDetailPanel.add(dadPosXStep); charDetailPanel.add(dadPosYStep);
		charDetailPanel.add(bfPosXStep);  charDetailPanel.add(bfPosYStep);
		charDetailPanel.add(gfPosXStep);  charDetailPanel.add(gfPosYStep);

		// small preview
		charPreview = new FlxSprite(pad, startY + 170).makeGraphic(PANEL_W - pad * 2, 80, 0xFF222244);
		charPreview.scrollFactor.set();
		charDetailPanel.add(charPreview);

		charDetailPanel.visible = false;
	}

	function refreshDetailPanel()
	{
		// show only the steppers relevant to the current sub tab
		dadCamXStep.visible = (charSubTab == 0); dadCamYStep.visible = (charSubTab == 0);
		bfCamXStep.visible  = (charSubTab == 1); bfCamYStep.visible  = (charSubTab == 1);
		gfCamXStep.visible  = (charSubTab == 2); gfCamYStep.visible  = (charSubTab == 2);
		dadPosXStep.visible = (charSubTab == 0); dadPosYStep.visible = (charSubTab == 0);
		bfPosXStep.visible  = (charSubTab == 1); bfPosYStep.visible  = (charSubTab == 1);
		gfPosXStep.visible  = (charSubTab == 2); gfPosYStep.visible  = (charSubTab == 2);

		// sync stepper values from stored data
		switch (charSubTab) {
			case 0: dadCamXStep.value = dadCamOffsetX; dadCamYStep.value = dadCamOffsetY; dadPosXStep.value = dadPosX; dadPosYStep.value = dadPosY;
			case 1: bfCamXStep.value  = bfCamOffsetX;  bfCamYStep.value  = bfCamOffsetY;  bfPosXStep.value  = bfPosX;  bfPosYStep.value  = bfPosY;
			case 2: gfCamXStep.value  = gfCamOffsetX;  gfCamYStep.value  = gfCamOffsetY;  gfPosXStep.value  = gfPosX;  gfPosYStep.value  = gfPosY;
		}
	}

	function refreshCharPreviews()
	{
		if (dadIcon != null) { dadIcon.changeIcon(dadName); }
		if (bfIcon  != null) { bfIcon.changeIcon(bfName);   }
		if (gfIcon  != null) { gfIcon.changeIcon(gfName);   }
	}

	// ─────────────────────────────────────────
	//  D-PAD
	// ─────────────────────────────────────────
	function buildDPad()
	{
		dpadGroup = new FlxGroup();
		add(dpadGroup);

		// position: bottom-left, above mini bar
		var baseX = 10;
		var baseY = FlxG.height - MINI_H - DPAD_SIZE - 10;
		var btnSz = Std.int(DPAD_SIZE / 3);

		dpadUp    = makeDPadBtn(baseX + btnSz,          baseY,          '▲');
		dpadDown  = makeDPadBtn(baseX + btnSz,          baseY + btnSz*2, '▼');
		dpadLeft  = makeDPadBtn(baseX,                  baseY + btnSz,  '◀');
		dpadRight = makeDPadBtn(baseX + btnSz * 2,      baseY + btnSz,  '▶');

		dpadGroup.add(dpadUp);
		dpadGroup.add(dpadDown);
		dpadGroup.add(dpadLeft);
		dpadGroup.add(dpadRight);
	}

	function makeDPadBtn(x:Float, y:Float, label:String):FlxButton
	{
		var sz = Std.int(DPAD_SIZE / 3);
		var btn = new FlxButton(x, y, label, null);
		btn.setGraphicSize(sz, sz);
		btn.updateHitbox();
		btn.label.setFormat(Paths.font('vcr.ttf'), 18, FlxColor.WHITE, CENTER);
		btn.color = 0xBB333366;
		btn.scrollFactor.set();
		return btn;
	}

	// ─────────────────────────────────────────
	//  MINI BAR (bottom center)
	// ─────────────────────────────────────────
	function buildMiniBar()
	{
		miniBar = new FlxGroup();
		add(miniBar);

		var barW  = FlxG.width - PANEL_W - 20;
		var barX  = PANEL_W + 10;
		var barY  = FlxG.height - MINI_H + 4;
		var pad   = 6;

		// background
		var bg = new FlxSprite(barX - pad, barY - pad).makeGraphic(barW + pad * 2, MINI_H, 0xCC0A0A1A);
		bg.scrollFactor.set();
		miniBar.add(bg);

		var border = new FlxSprite(barX - pad, barY - pad).makeGraphic(barW + pad * 2, 2, 0xFF5555AA);
		border.scrollFactor.set();
		miniBar.add(border);

		var btnW = Std.int((barW - pad * 2) / 3) - pad;
		var btnH = MINI_H - pad * 2 - 4;

		// Camera teleport buttons
		var dadCamBtn = new FlxButton(barX, barY + 2, 'Dad Cam', function() { gotoCharCam(0); });
		dadCamBtn.setGraphicSize(btnW, btnH);
		dadCamBtn.updateHitbox();
		dadCamBtn.label.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, CENTER);
		dadCamBtn.color = 0xFF553399;
		dadCamBtn.scrollFactor.set();
		miniBar.add(dadCamBtn);

		var gfCamBtn = new FlxButton(barX + btnW + pad, barY + 2, 'GF Cam', function() { gotoCharCam(2); });
		gfCamBtn.setGraphicSize(btnW, btnH);
		gfCamBtn.updateHitbox();
		gfCamBtn.label.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, CENTER);
		gfCamBtn.color = 0xFF336644;
		gfCamBtn.scrollFactor.set();
		miniBar.add(gfCamBtn);

		var bfCamBtn = new FlxButton(barX + (btnW + pad) * 2, barY + 2, 'BF Cam', function() { gotoCharCam(1); });
		bfCamBtn.setGraphicSize(btnW, btnH);
		bfCamBtn.updateHitbox();
		bfCamBtn.label.setFormat(Paths.font('vcr.ttf'), 12, FlxColor.WHITE, CENTER);
		bfCamBtn.color = 0xFF224477;
		bfCamBtn.scrollFactor.set();
		miniBar.add(bfCamBtn);
	}

	function gotoCharCam(who:Int)
	{
		// Teleport camera to character's position + cam offset
		switch (who) {
			case 0: camFollow.setPosition(dadPosX + dadCamOffsetX, dadPosY + dadCamOffsetY);
			case 1: camFollow.setPosition(bfPosX  + bfCamOffsetX,  bfPosY  + bfCamOffsetY);
			case 2: camFollow.setPosition(gfPosX  + gfCamOffsetX,  gfPosY  + gfCamOffsetY);
		}
	}

	// ─────────────────────────────────────────
	//  HELPERS
	// ─────────────────────────────────────────
	function makeStepper(x:Float, y:Float, step:Float, val:Float, min:Float, max:Float, name:String):FlxUINumericStepper
	{
		var s = new FlxUINumericStepper(x, y, step, val, min, max, 1);
		s.name = name;
		s.scrollFactor.set();
		blockTypingOnStepper.push(s);
		return s;
	}

	// ─────────────────────────────────────────
	//  UPDATE
	// ─────────────────────────────────────────
	override function update(elapsed:Float)
	{
		super.update(elapsed);

		// Block keyboard shortcuts while typing
		var typing = false;
		for (inp in blockTypingOn) if (inp.hasFocus) { typing = true; break; }

		if (!typing) {
			handleDPad();
			handleKeyboard();
		}

		// Sync stepper values to data
		syncSteppers();
	}

	function handleDPad()
	{
		var dx:Float = 0;
		var dy:Float = 0;

		// Touch / mouse pressed on d-pad buttons
		if (dpadUp.pressed)    dy = -moveSpeed;
		if (dpadDown.pressed)  dy =  moveSpeed;
		if (dpadLeft.pressed)  dx = -moveSpeed;
		if (dpadRight.pressed) dx =  moveSpeed;

		// Also support keyboard arrows
		if (FlxG.keys.pressed.UP)    dy = -moveSpeed;
		if (FlxG.keys.pressed.DOWN)  dy =  moveSpeed;
		if (FlxG.keys.pressed.LEFT)  dx = -moveSpeed;
		if (FlxG.keys.pressed.RIGHT) dx =  moveSpeed;
		if (FlxG.keys.pressed.SHIFT) { dx *= 4; dy *= 4; }

		if (selectedSprite != null && (dx != 0 || dy != 0)) {
			selectedSprite.x += dx;
			selectedSprite.y += dy;
		} else if (dx != 0 || dy != 0) {
			// move camera
			camFollow.x += dx;
			camFollow.y += dy;
		}
	}

	function handleKeyboard()
	{
		// ESC = back to menu
		if (FlxG.keys.justPressed.ESCAPE) {
			FlxG.mouse.visible = false;
			MusicBeatState.switchState(new MainMenuState());
		}

		// CTRL+S = save
		if (FlxG.keys.pressed.CONTROL && FlxG.keys.justPressed.S) {
			saveStage();
		}
	}

	function syncSteppers()
	{
		switch (charSubTab) {
			case 0:
				dadCamOffsetX = dadCamXStep.value; dadCamOffsetY = dadCamYStep.value;
				dadPosX       = dadPosXStep.value;  dadPosY       = dadPosYStep.value;
			case 1:
				bfCamOffsetX = bfCamXStep.value; bfCamOffsetY = bfCamYStep.value;
				bfPosX       = bfPosXStep.value;  bfPosY       = bfPosYStep.value;
			case 2:
				gfCamOffsetX = gfCamXStep.value; gfCamOffsetY = gfCamYStep.value;
				gfPosX       = gfPosXStep.value;  gfPosY       = gfPosYStep.value;
		}
	}

	// ─────────────────────────────────────────
	//  SAVE
	// ─────────────────────────────────────────
	function saveStage()
	{
		// Build stage JSON (Psych Engine stage format)
		var stageJson:Dynamic = {
			directory: selectedStage,
			defaultZoom: 0.9,
			isPixelStage: false,
			boyfriend: [bfPosX, bfPosY],
			girlfriend: [gfPosX, gfPosY],
			opponent: [dadPosX, dadPosY],
			hide_girlfriend: false,
			camera_boyfriend: [bfCamOffsetX, bfCamOffsetY],
			camera_opponent: [dadCamOffsetX, dadCamOffsetY],
			camera_girlfriend: [gfCamOffsetX, gfCamOffsetY],
			camera_speed: 1,
			objects: buildObjectList()
		};

		var data:String = haxe.Json.stringify(stageJson, '\t');

		// Build stage Lua (basic template)
		var lua:String = buildStageLua();

		#if mobile
		StorageUtil.saveContent('${selectedStage}.json', data.trim());
		StorageUtil.saveContent('${selectedStage}.lua', lua);
		#elseif sys
		// Save to mods stages folder
		var jsonPath = Paths.mods(Mods.currentModDirectory + '/stages/${selectedStage}.json');
		var luaPath  = Paths.mods(Mods.currentModDirectory + '/stages/${selectedStage}.lua');

		try {
			// ensure folder exists
			var dir = Path.directory(jsonPath);
			if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
			File.saveContent(jsonPath, data.trim());
			File.saveContent(luaPath, lua);
			trace('Stage saved: $jsonPath');
		} catch(e) {
			trace('Save error: $e');
			// Fallback to FileReference
			_file = new FileReference();
			_file.addEventListener(Event.COMPLETE, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data.trim(), selectedStage + '.json');
		}
		#else
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.addEventListener(Event.CANCEL, onSaveCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file.save(data.trim(), selectedStage + '.json');
		#end

		showSaveToast();
	}

	function buildObjectList():Array<Dynamic>
	{
		var objs:Array<Dynamic> = [];
		for (entry in importedSprites) {
			objs.push({
				assetPath: entry.name,
				libraryName: '',
				name: Path.withoutDirectory(entry.name),
				x: entry.spr.x - PANEL_W,
				y: entry.spr.y,
				scrollFactor_x: 1.0,
				scrollFactor_y: 1.0,
				angle: 0,
				alpha: 1,
				color: 'FFFFFFFF',
				scale_x: 1,
				scale_y: 1,
				updateHitbox: true,
				antialiasing: true,
				layer: 'stage',
				animations: [],
				startingAnim: '',
				special_anim: false,
				imageFile: entry.name,
				hexColor: 'ffffff',
				isAnimated: false,
				visible: true
			});
		}
		return objs;
	}

	function buildStageLua():String
	{
		var sb = new StringBuf();
		sb.add('-- Stage: ${selectedStage} | Generated by Stage Editor\n');
		sb.add('-- Characters: Dad=${dadName}, BF=${bfName}, GF=${gfName}\n\n');
		sb.add('function onCreate()\n');
		sb.add('\tsetProperty("defaultCamZoom", 0.9)\n');
		for (entry in importedSprites) {
			var n = Path.withoutDirectory(entry.name);
			sb.add('\tmakeLuaSprite("${n}", "${entry.name}", ${Std.int(entry.spr.x - PANEL_W)}, ${Std.int(entry.spr.y)})\n');
			sb.add('\taddLuaSprite("${n}", false)\n');
		}
		sb.add('end\n');
		return sb.toString();
	}

	function showSaveToast()
	{
		var toast = new FlxText(FlxG.width / 2 - 150, FlxG.height - 130, 300, 'Saved! ✓', 20);
		toast.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.GREEN, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		toast.borderSize = 2;
		toast.scrollFactor.set();
		add(toast);
		new FlxTimer().start(2, function(_) { remove(toast); toast.destroy(); });
	}

	function onSaveComplete(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice('Stage saved successfully.');
	}

	function onSaveCancel(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
	}

	function onSaveError(_):Void
	{
		_file.removeEventListener(Event.COMPLETE, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error('Error saving stage.');
	}
}
