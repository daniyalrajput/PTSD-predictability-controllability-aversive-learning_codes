%% ACCURACY ANALYSIS: TWO GROUPS, TWO CONDITIONS, THREE PREDICTABILITY LEVELS
% Public archive version: a configurable MATLAB analysis script.
%
% REQUIREMENTS
% MATLAB R2020b or later; Statistics and Machine Learning Toolbox.
% No separate helper files are required. All helpers are defined below.
%
% INPUT FORMAT
% Four Excel workbooks: one per group and condition. Each worksheet contains
% one participant's trial data, with a header row. Worksheet names are the
% participant IDs and MUST match exactly between the two conditions within
% each group. Names must be unique within a workbook. Do not include summary
% worksheets. IDs do not need to match between groups.
% blockCol: column containing block labels (e.g., Block1).
% groupACorrCol/groupBCorrCol: correctness column. Accepted values: numeric
% 1/0 or text correct/incorrect, true/false, or 1/0 (case insensitive).
% Empty correctness cells are omitted; unrecognized nonempty values cause
% an error. Accuracy = 100 * correct valid trials / all valid trials.
% Block labels are matched exactly after trimming surrounding whitespace.
%
% CONFIGURATION
% Edit the four filenames, block lists, column indices, and output directory.
% The block lists below retain the source script's six-block selection;
% change them to include ALL intended blocks for your dataset.
% S1 is labelled Controllable and S2 Uncontrollable throughout this script.
% Group labels are generic (Group A and Group B).
%
% ANALYSIS CHOICES
% Cell-wise values beyond mean +/- 3 SD are set to NaN once, within group.
% Complete cases are required for the repeated-measures ANOVA. Optional
% balancing reproduces the source script's sorted-ID truncation; it is not
% required by the model and discards participants. Set BALANCE_GROUPS=true
% below to retain all complete participants. These choices can alter results.
% Posthoc Bonferroni families: 6 between-group tests, 6 paired condition
% tests, and 12 paired predictability tests. These are separate families.
%
% OUTPUTS
% Figure PNG (600 dpi), vector PDF, Excel statistics, MAT workspace and log.
% This archive contains code only, not participant data. Exported participant
% IDs and MAT workspaces require review before making outputs public.
% Original dataset-specific helpers were not supplied; input handling below
% is explicitly defined and must be checked against your workbook format.
% Runtime validation with the original data has not been performed.
% Author: Daniyal Rajput, University of Melbourne. Written by the author.



clear; clc; close all;
rng(1, 'twister'); % Reproducible plotting jitter.
%% =============================== USER CONTROLS ===============================
groupAFiles = struct('S1','group_a_condition_1.xlsx', ...
                     'S2','group_a_condition_2.xlsx');
groupBFiles = struct('S1','group_b_condition_1.xlsx', ...
                     'S2','group_b_condition_2.xlsx');
HP_blocks = ["Block1","Block5"];
MP_blocks = ["Block3","Block4"];
UP_blocks = ["Block2","Block6"];
blockCol = 2;
groupACorrCol = 13;   % Group A correctness col
groupBCorrCol    = 8;    % Group B correctness col
outdir = fullfile(pwd, 'accuracy_outputs');
colBox = [0.68 0.68 0.68];
colGroupACtrl = [0.05 0.20 0.55];
colGroupAUnc  = [0.38 0.68 0.95];
colGroupBCtrl = [0.60 0.10 0.10];
colGroupBUnc  = [0.92 0.62 0.62];   % light red
fs_title = 20; fs_xtick = 22; fs_ytick = 20; fs_label = 18; fs_legend = 18;
lw_axes = 1.6; lw_box = 1.2;
ms_dot = 40; alpha_box = 0.22; alpha_dot = 0.90;
boxWidth = 0.35;
jitterFracOfHalfBox = 0.85;
dotJitter = (boxWidth/2) * jitterFracOfHalfBox;
png_dpi = 600;
DO_3SD_REMOVE = true;      % turn on/off
DO_COMPLETE_CASE = true;   % remove subjects with any NaN across the 6 cells after 3SD
%% =============================== OUTPUT + LOG ===============================
if ~exist(outdir,'dir')
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory:\n%s\nReason: %s', outdir, msg); end
end
log_txt = fullfile(outdir,'Figure2_Accuracy_GroupAvsGroupB_RunLog.txt');
if exist(log_txt,'file'), delete(log_txt); end
diary(log_txt);
fprintf('============================================================\n');
fprintf('ACCURACY Group A vs Group B (2x2x3) | Output: %s\n', outdir);
fprintf('Group A: %s | %s\n', groupAFiles.S1, groupAFiles.S2);
fprintf('Group B:    %s | %s\n', groupBFiles.S1, groupBFiles.S2);
fprintf('Cols: blockCol=%d | groupACorrCol=%d | groupBCorrCol=%d\n', blockCol, groupACorrCol, groupBCorrCol);
fprintf('Blocks: HP=%s | MP=%s | UP=%s\n', strjoin(HP_blocks,','), strjoin(MP_blocks,','), strjoin(UP_blocks,','));
fprintf('3SD: DO_3SD_REMOVE=%d | DO_COMPLETE_CASE=%d\n', DO_3SD_REMOVE, DO_COMPLETE_CASE);
fprintf('Timestamp: %s\n', datestr(now));
fprintf('============================================================\n\n');
%% =============================== 1) READ ACCURACY PER SHEET ===============================
H_S1_raw = local_read_accuracy_excel(groupAFiles.S1, blockCol, groupACorrCol, "group_a", HP_blocks, MP_blocks, UP_blocks);
H_S2_raw = local_read_accuracy_excel(groupAFiles.S2, blockCol, groupACorrCol, "group_a", HP_blocks, MP_blocks, UP_blocks);
P_S1_raw = local_read_accuracy_excel(groupBFiles.S1,    blockCol, groupBCorrCol,    "group_b",    HP_blocks, MP_blocks, UP_blocks);
P_S2_raw = local_read_accuracy_excel(groupBFiles.S2,    blockCol, groupBCorrCol,    "group_b",    HP_blocks, MP_blocks, UP_blocks);
%% =============================== 2) WITHIN-GROUP MATCH (S1 vs S2) ===============================
[H, msgH] = local_match_S1S2_within_group(H_S1_raw, H_S2_raw, "Group A");
[P, msgP] = local_match_S1S2_within_group(P_S1_raw, P_S2_raw, "Group B");
fprintf('\n--- Within-group matching ---\n%s\n%s\n', msgH, msgP);
%% =============================== 2.5) ±3 SD OUTLIER REMOVAL (CELL-WISE) ===============================
outlier_report = table('Size',[0 6], ...
    'VariableTypes', {'string','string','string','double','double','double'}, ...
    'VariableNames', {'Group','Control','Predictability','N_before','N_removed','N_after'});
if DO_3SD_REMOVE
    fprintf('\n--- ±3 SD outlier removal (cell-wise) ---\n');
    rm3sd = @(x) local_rm3sd_inline(x);
    [H.HP_S1, nb,nr,na] = rm3sd(H.HP_S1); outlier_report(end+1,:) = {"Group A","Controllable","HP",nb,nr,na};
    [H.MP_S1, nb,nr,na] = rm3sd(H.MP_S1); outlier_report(end+1,:) = {"Group A","Controllable","MP",nb,nr,na};
    [H.UP_S1, nb,nr,na] = rm3sd(H.UP_S1); outlier_report(end+1,:) = {"Group A","Controllable","UP",nb,nr,na};
    [H.HP_S2, nb,nr,na] = rm3sd(H.HP_S2); outlier_report(end+1,:) = {"Group A","Uncontrollable","HP",nb,nr,na};
    [H.MP_S2, nb,nr,na] = rm3sd(H.MP_S2); outlier_report(end+1,:) = {"Group A","Uncontrollable","MP",nb,nr,na};
    [H.UP_S2, nb,nr,na] = rm3sd(H.UP_S2); outlier_report(end+1,:) = {"Group A","Uncontrollable","UP",nb,nr,na};
    [P.HP_S1, nb,nr,na] = rm3sd(P.HP_S1); outlier_report(end+1,:) = {"Group B","Controllable","HP",nb,nr,na};
    [P.MP_S1, nb,nr,na] = rm3sd(P.MP_S1); outlier_report(end+1,:) = {"Group B","Controllable","MP",nb,nr,na};
    [P.UP_S1, nb,nr,na] = rm3sd(P.UP_S1); outlier_report(end+1,:) = {"Group B","Controllable","UP",nb,nr,na};
    [P.HP_S2, nb,nr,na] = rm3sd(P.HP_S2); outlier_report(end+1,:) = {"Group B","Uncontrollable","HP",nb,nr,na};
    [P.MP_S2, nb,nr,na] = rm3sd(P.MP_S2); outlier_report(end+1,:) = {"Group B","Uncontrollable","MP",nb,nr,na};
    [P.UP_S2, nb,nr,na] = rm3sd(P.UP_S2); outlier_report(end+1,:) = {"Group B","Uncontrollable","UP",nb,nr,na};
    disp(outlier_report);
end
if DO_COMPLETE_CASE
        okH = isfinite(H.HP_S1) & isfinite(H.MP_S1) & isfinite(H.UP_S1) & ...
              isfinite(H.HP_S2) & isfinite(H.MP_S2) & isfinite(H.UP_S2);
        okP = isfinite(P.HP_S1) & isfinite(P.MP_S1) & isfinite(P.UP_S1) & ...
              isfinite(P.HP_S2) & isfinite(P.MP_S2) & isfinite(P.UP_S2);
        nH0 = numel(H.id); nP0 = numel(P.id);
        H = local_subset_group(H, find(okH));
        P = local_subset_group(P, find(okP));
        fprintf('Complete-case after 3SD: Group A %d -> %d | Group B %d -> %d\n', nH0, numel(H.id), nP0, numel(P.id));
end
if ~DO_COMPLETE_CASE
    error('This ANOVA workflow requires DO_COMPLETE_CASE=true.');
end
%% =============================== 3) BALANCE GROUPS (same N) ===============================
BALANCE_GROUPS = true; % Original analysis: retain first N sorted IDs per group.
N_H = numel(H.id);
N_P = numel(P.id);
N   = min(N_H, N_P);
if N < 3
    error('Too few matched subjects after cleanup. Group A=%d, Group B=%d', N_H, N_P);
end
[~, idxH] = sort(H.id);
[~, idxP] = sort(P.id);
if BALANCE_GROUPS
    H = local_subset_group(H, idxH(1:N));
    P = local_subset_group(P, idxP(1:N));
else
    H = local_subset_group(H, idxH);
    P = local_subset_group(P, idxP);
end
fprintf('Retained: Group A=%d | Group B=%d\n', numel(H.id), numel(P.id));
fprintf('Available complete cases: Group A=%d | Group B=%d; balancing=%d\n', N_H, N_P, BALANCE_GROUPS);
%% =============================== 4) DESCRIPTIVES ===============================
meanSEM = @(x) [mean(x,'omitnan'), std(x,'omitnan')/sqrt(sum(~isnan(x)))];
desc = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Group','Control','Predictability','MeanAcc','SEMAcc'});
desc = [desc; local_desc_rows("Group A","Controllable",   H.HP_S1, H.MP_S1, H.UP_S1, meanSEM)];
desc = [desc; local_desc_rows("Group A","Uncontrollable", H.HP_S2, H.MP_S2, H.UP_S2, meanSEM)];
desc = [desc; local_desc_rows("Group B","Controllable",      P.HP_S1, P.MP_S1, P.UP_S1, meanSEM)];
desc = [desc; local_desc_rows("Group B","Uncontrollable",    P.HP_S2, P.MP_S2, P.UP_S2, meanSEM)];
disp('===== Descriptives (Accuracy %, Mean ± SEM) =====');
disp(desc);
%% =============================== 5) FINAL FIGURE ===============================
FIG_WIDTH  = 1600;
FIG_HEIGHT = 750;
fig = figure('Color','w', ...
    'Units','pixels', ...
    'Position',[100 100 FIG_WIDTH FIG_HEIGHT]);
tiledlayout(1,3, ...
    'TileSpacing','compact', ...
    'Padding','normal');
%% ========================= SIZE / STYLE VARIABLES =========================
TITLE_SIZE     = 24;
YLABEL_SIZE    = 26;
XTICK_SIZE     = 20;
YTICK_SIZE     = 24;
LEGEND_SIZE    = 20;
AXIS_LINE_W    = 1.6;
BOX_LINE_W     = 1.4;
BOX_WIDTH      = 0.42;
DOT_SIZE       = 44;
MEAN_DOT_SIZE  = 95;
ERROR_LINE_W   = 1.5;
ERROR_CAP_SIZE = 8;
JITTER_AMOUNT  = 0.16;
X_LABEL_GAP    = 0;
Y_LABEL_X      = -0.14;
%% apply figure size
fig.Position = [100 100 FIG_WIDTH FIG_HEIGHT];
%% ========================= X POSITIONS =========================
x1 = 1;
x2 = 2;
x3 = 3.2;
x4 = 4.2;
predTitles = {'Highly predictable', ...
              'Moderately predictable', ...
              'Unpredictable'};
%% ========================= LOOP =========================
for c = 1:3
    ax = nexttile;
    hold(ax,'on');
    %% ========================= SELECT DATA =========================
    switch c
        case 1
            HC = H.HP_S1;
            PC = P.HP_S1;
            HU = H.HP_S2;
            PU = P.HP_S2;
        case 2
            HC = H.MP_S1;
            PC = P.MP_S1;
            HU = H.MP_S2;
            PU = P.MP_S2;
        case 3
            HC = H.UP_S1;
            PC = P.UP_S1;
            HU = H.UP_S2;
            PU = P.UP_S2;
    end
    HC = HC(:);
    PC = PC(:);
    HU = HU(:);
    PU = PU(:);
    %% ========================= BOX PLOTS =========================
    boxchart(x1*ones(size(HC)), HC, ...
        'BoxFaceColor', colBox, ...
        'BoxFaceAlpha', 0.28, ...
        'BoxWidth', BOX_WIDTH, ...
        'MarkerStyle','none', ...
        'LineWidth', BOX_LINE_W);
    boxchart(x2*ones(size(PC)), PC, ...
        'BoxFaceColor', colBox, ...
        'BoxFaceAlpha', 0.28, ...
        'BoxWidth', BOX_WIDTH, ...
        'MarkerStyle','none', ...
        'LineWidth', BOX_LINE_W);
    boxchart(x3*ones(size(HU)), HU, ...
        'BoxFaceColor', colBox, ...
        'BoxFaceAlpha', 0.28, ...
        'BoxWidth', BOX_WIDTH, ...
        'MarkerStyle','none', ...
        'LineWidth', BOX_LINE_W);
    boxchart(x4*ones(size(PU)), PU, ...
        'BoxFaceColor', colBox, ...
        'BoxFaceAlpha', 0.28, ...
        'BoxWidth', BOX_WIDTH, ...
        'MarkerStyle','none', ...
        'LineWidth', BOX_LINE_W);
%% ========================= DOTS =========================
jitter = @(n) (rand(n,1)-0.5)*2*JITTER_AMOUNT;
scatter(x1+jitter(numel(HC)), HC, ...
    DOT_SIZE, colGroupACtrl, ...
    'filled', ...
    'MarkerEdgeColor','k');
scatter(x2+jitter(numel(PC)), PC, ...
    DOT_SIZE, colGroupBCtrl, ...
    'filled', ...
    'MarkerEdgeColor','k');
scatter(x3+jitter(numel(HU)), HU, ...
    DOT_SIZE, colGroupAUnc, ...
    'filled', ...
    'MarkerEdgeColor','k');
scatter(x4+jitter(numel(PU)), PU, ...
    DOT_SIZE, colGroupBUnc, ...
    'filled', ...
    'MarkerEdgeColor','k');
    %% ========================= MEAN ± SEM =========================
    allY = {HC, PC, HU, PU};
    allX = [x1 x2 x3 x4];
    for i = 1:4
        yy = allY{i};
        m = mean(yy,'omitnan');
        sem = std(yy,'omitnan') ./ sqrt(sum(~isnan(yy)));
        errorbar(allX(i), m, sem, ...
            'k', ...
            'LineWidth', ERROR_LINE_W, ...
            'CapSize', ERROR_CAP_SIZE);
        scatter(allX(i), m, ...
            MEAN_DOT_SIZE, ...
            'k', ...
            'filled');
    end
    %% ========================= AXES =========================
    xlim([0.4 4.8]);
    ylim([0 100]);
    ax.Box = 'off';
    ax.LineWidth = AXIS_LINE_W;
    ax.FontSize = XTICK_SIZE;
    ax.TickDir = 'out';
    %% real x-axis labels
    ax.XTick = [1.5 3.7];
    ax.XTickLabel = {'Controllable','Uncontrollable'};
    ax.XAxis.FontSize = XTICK_SIZE;
    ax.XColor = 'k';
    try
        ax.XRuler.TickLabelGapOffset = X_LABEL_GAP;
    catch
    end
    %% y-axis
    if c == 1
        ax.YTick = 0:20:100;
        ax.YAxis.FontSize = YTICK_SIZE;
        ax.YColor = 'k';
        ylabel('Accuracy (%)', ...
            'FontSize', YLABEL_SIZE, ...
            'FontWeight','bold');
    else
        ax.YTick = [];
        ax.YColor = 'none';
    end
    %% title
    title(predTitles{c}, ...
        'FontSize', TITLE_SIZE, ...
        'FontWeight','bold');
    %% ========================= LEGEND =========================
    if c == 3
        legend off
        h1 = scatter(nan,nan,70,...
            colGroupACtrl,...
            'filled',...
            'MarkerEdgeColor','k');
        h2 = scatter(nan,nan,70,...
            colGroupAUnc,...
            'filled',...
            'MarkerEdgeColor','k');
        h3 = scatter(nan,nan,70,...
            colGroupBCtrl,...
            'filled',...
            'MarkerEdgeColor','k');
        h4 = scatter(nan,nan,70,...
            colGroupBUnc,...
            'filled',...
            'MarkerEdgeColor','k');
        lgd = legend([h1 h2 h3 h4], ...
            {'Group A controllable', ...
             'Group A uncontrollable', ...
             'Group B controllable', ...
             'Group B uncontrollable'});
        lgd.Box = 'off';
        lgd.FontSize = LEGEND_SIZE;
        lgd.Units = 'normalized';
        lgd.Position = [0.78 0.72 0.15 0.18];
    end
end
%% ========================= SAVE =========================
fig_png = fullfile(outdir, ...
    sprintf('Figure2_Accuracy_GroupAvsGroupB_%ddpi.png', png_dpi));
fig_pdf = fullfile(outdir, ...
    'Figure2_Accuracy_GroupAvsGroupB_vector.pdf');
exportgraphics(fig, fig_png, 'Resolution', png_dpi);
exportgraphics(fig, fig_pdf, 'ContentType','vector');
fprintf('Saved figure:\n%s\n%s\n', fig_png, fig_pdf);
%% =============================== 6) 2×2×3 MIXED RM ANOVA ===============================
T_H = table("H_"+H.id, categorical(repmat("Group A", numel(H.id),1)), ...
    H.HP_S1, H.MP_S1, H.UP_S1, H.HP_S2, H.MP_S2, H.UP_S2, ...
    'VariableNames', {'Subject','Group','HP_S1','MP_S1','UP_S1','HP_S2','MP_S2','UP_S2'});
T_P = table("P_"+P.id, categorical(repmat("Group B", numel(P.id),1)), ...
    P.HP_S1, P.MP_S1, P.UP_S1, P.HP_S2, P.MP_S2, P.UP_S2, ...
    'VariableNames', {'Subject','Group','HP_S1','MP_S1','UP_S1','HP_S2','MP_S2','UP_S2'});
Twide = [T_H; T_P];
Within = table( ...
    categorical({'Controllable';'Controllable';'Controllable';'Uncontrollable';'Uncontrollable';'Uncontrollable'}), ...
    categorical({'HP';'MP';'UP';'HP';'MP';'UP'}), ...
    'VariableNames', {'Control','Predictability'});
rm = fitrm(Twide, 'HP_S1-UP_S2 ~ Group', 'WithinDesign', Within);
ranovatbl = ranova(rm, 'WithinModel', 'Control*Predictability');
between_anova = anova(rm);
rn = string(ranovatbl.Properties.RowNames);
ranovatbl = addvars(ranovatbl, rn, 'Before', ranovatbl.Properties.VariableNames{1}, 'NewVariableNames','Effect');
ranovatbl.Properties.RowNames = {};
Eta_p2 = nan(height(ranovatbl),1);
for i = 1:height(ranovatbl)
    eff = string(ranovatbl.Effect(i));
    if startsWith(eff,"Error"), continue; end
    parts = split(eff, ':');
    withinParts = parts(parts ~= "Group" & parts ~= "(Intercept)");
    if isempty(withinParts)
        errName = "Error";
    else
        errName = "Error(" + strjoin(withinParts, ':') + ")";
    end
    idx_err = find(rn == errName, 1);
    if ~isempty(idx_err) && ismember("SumSq", ranovatbl.Properties.VariableNames)
        SS_eff = ranovatbl.SumSq(i);
        SS_err = ranovatbl.SumSq(idx_err);
        Eta_p2(i) = SS_eff / (SS_eff + SS_err);
    end
end
ranovatbl.Eta_p2 = Eta_p2;
isEffectRow = ~startsWith(string(ranovatbl.Effect), "Error") & string(ranovatbl.Effect) ~= "(Intercept)";
effect_summary = ranovatbl(isEffectRow, intersect(ranovatbl.Properties.VariableNames, {'Effect','DF','F','pValue','Eta_p2','SumSq'}));
disp('===== 2×2×3 MIXED ANOVA (Accuracy) + ηp² =====');
disp(effect_summary);
%% =============================== 7) POSTHOCS (manual comparisons) ===============================
preds = ["HP","MP","UP"];
ctrls = ["Controllable","Uncontrollable"];
groups = ["Group A","Group B"];
getCell = @(G,C,PR) local_get_cell(H,P,G,C,PR);
between_tbl = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Control','Predictability','t','df','p_unc','p_bonf'});
for ci = 1:numel(ctrls)
    for pi = 1:numel(preds)
        C  = ctrls(ci);
        PR = preds(pi);
        yH = getCell("Group A", C, PR);
        yP = getCell("Group B",    C, PR);
        [~,p,~,st] = ttest2(yH, yP, 'Vartype','unequal'); % Welch
        between_tbl = [between_tbl; table(C,PR,st.tstat,st.df,p,NaN, ...
            'VariableNames',between_tbl.Properties.VariableNames)]; %#ok<AGROW>
    end
end
between_tbl.p_bonf = min(between_tbl.p_unc * 6, 1);
within_control_tbl = table(strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Group','Predictability','t','df','p_unc','p_bonf'});
for gi = 1:numel(groups)
    for pi = 1:numel(preds)
        G  = groups(gi);
        PR = preds(pi);
        yS1 = getCell(G, "Controllable",   PR);
        yS2 = getCell(G, "Uncontrollable", PR);
        [~,p,~,st] = ttest(yS1, yS2); % paired
        within_control_tbl = [within_control_tbl; table(G,PR,st.tstat,st.df,p,NaN, ...
            'VariableNames',within_control_tbl.Properties.VariableNames)]; %#ok<AGROW>
    end
end
within_control_tbl.p_bonf = min(within_control_tbl.p_unc * 6, 1);
pairs = ["HP","MP"; "HP","UP"; "MP","UP"];
within_pred_tbl = table(strings(0,1), strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'Group','Control','Comparison','t','df','p_unc','p_bonf'});
for gi = 1:numel(groups)
    for ci = 1:numel(ctrls)
        G = groups(gi);
        C = ctrls(ci);
        for k = 1:size(pairs,1)
            A = pairs(k,1); B = pairs(k,2);
            yA = getCell(G,C,A);
            yB = getCell(G,C,B);
            [~,p,~,st] = ttest(yA,yB); % paired
            comp = A + " vs " + B;
            within_pred_tbl = [within_pred_tbl; table(G,C,comp,st.tstat,st.df,p,NaN, ...
                'VariableNames',within_pred_tbl.Properties.VariableNames)]; %#ok<AGROW>
        end
    end
end
within_pred_tbl.p_bonf = min(within_pred_tbl.p_unc * 12, 1);
disp('===== Posthoc BETWEEN (Group A vs Group B) per cell (Bonferroni) ====='); disp(between_tbl);
disp('===== Posthoc WITHIN CONTROL (S1 vs S2) per Group×Pred (Bonferroni) ====='); disp(within_control_tbl);
disp('===== Posthoc WITHIN PREDICTABILITY (Bonferroni) ====='); disp(within_pred_tbl);
%% =============================== 8) SAVE OUTPUTS ===============================
stats_xlsx = fullfile(outdir,'Figure2_Accuracy_GroupAvsGroupB_STATS.xlsx');
mat_out    = fullfile(outdir,'Figure2_Accuracy_GroupAvsGroupB_AllOutputs.mat');
writetable(desc,           stats_xlsx, 'Sheet','Descriptives');
if DO_3SD_REMOVE
    writetable(outlier_report, stats_xlsx, 'Sheet','OutlierReport_3SD');
end
writetable(ranovatbl,      stats_xlsx, 'Sheet','ANOVA_full');
writetable(between_anova, stats_xlsx, 'Sheet','ANOVA_between', 'WriteRowNames',true);
writetable(effect_summary, stats_xlsx, 'Sheet','ANOVA_effects_eta_p2');
writetable(between_tbl,    stats_xlsx, 'Sheet','Posthoc_Between');
writetable(within_control_tbl, stats_xlsx, 'Sheet','Posthoc_Within_Control');
writetable(within_pred_tbl,    stats_xlsx, 'Sheet','Posthoc_Within_Pred');
save(mat_out, ...
    'H_S1_raw','H_S2_raw','P_S1_raw','P_S2_raw','H','P','Twide','Within','rm', ...
    'ranovatbl','between_anova','effect_summary','desc','between_tbl','within_control_tbl','within_pred_tbl', ...
    'outlier_report','fig_png','fig_pdf','outdir', ...
    'groupAFiles','groupBFiles','groupACorrCol','groupBCorrCol','blockCol', ...
    'HP_blocks','MP_blocks','UP_blocks', ...
    'DO_3SD_REMOVE','DO_COMPLETE_CASE','BALANCE_GROUPS');
fprintf('\n DONE — saved:\n%s\n%s\n%s\n%s\n', fig_png, fig_pdf, stats_xlsx, mat_out);
diary off;
%% =============================== LOCAL (script-only) ===============================

function S = local_read_accuracy_excel(file, blockCol, corrCol, ~, hp, mp, up)
    if ~isfile(file), error('Input workbook not found: %s', file); end
    sheets = string(sheetnames(file));
    S = struct('id', sheets(:), 'HP', nan(numel(sheets),1), ...
        'MP', nan(numel(sheets),1), 'UP', nan(numel(sheets),1));
    blockSets = {hp,mp,up}; names = {'HP','MP','UP'};
    for i = 1:numel(sheets)
        T = readtable(file, 'Sheet', sheets(i), 'VariableNamingRule','preserve');
        if width(T) < max(blockCol,corrCol)
            error('Insufficient columns in %s, sheet %s.',file,sheets(i));
        end
        blocks = strtrim(string(T{:,blockCol}));
        raw = T{:,corrCol};
        if isnumeric(raw) || islogical(raw)
            correct = double(raw);
            bad = ~isnan(correct) & correct ~= 0 & correct ~= 1;
        else
            values = lower(strtrim(string(raw)));
            correct = nan(size(values));
            correct(ismember(values,["1","true","correct"])) = 1;
            correct(ismember(values,["0","false","incorrect"])) = 0;
            empty = ismissing(values) | values == "";
            bad = ~empty & isnan(correct);
        end
        if any(bad)
            error('Unrecognized correctness value in %s, sheet %s.',file,sheets(i));
        end
        correct = correct(:);
        for j = 1:3
            keep = ismember(blocks, blockSets{j}) & isfinite(correct);
            if any(keep), S.(names{j})(i) = 100 * mean(correct(keep)); end
        end
    end
end

function [G,msg] = local_match_S1S2_within_group(S1,S2,label)
    [ids,i1,i2] = intersect(S1.id,S2.id,'stable');
    G = struct('id',ids(:));
    names = {'HP','MP','UP'};
    for j = 1:3
        G.([names{j},'_S1']) = S1.(names{j})(i1);
        G.([names{j},'_S2']) = S2.(names{j})(i2);
    end
    msg = sprintf('%s: S1=%d, S2=%d, matched=%d; unmatched S1=%d, S2=%d.', ...
        label,numel(S1.id),numel(S2.id),numel(ids), ...
        numel(S1.id)-numel(ids),numel(S2.id)-numel(ids));
end

function G = local_subset_group(G,idx)
    names = fieldnames(G);
    for j = 1:numel(names), G.(names{j}) = G.(names{j})(idx); end
end

function [x,nb,nr,na] = local_rm3sd_inline(x)
    x = x(:); valid = isfinite(x); nb = sum(valid);
    remove = false(size(x));
    if nb >= 3
        m = mean(x(valid)); s = std(x(valid));
        if s > 0, remove = valid & abs(x-m) > 3*s; end
    end
    x(remove) = NaN; nr = sum(remove); na = sum(isfinite(x));
end

function T = local_desc_rows(group,control,hp,mp,up,meanSEM)
    values = {hp,mp,up}; labels = ["HP";"MP";"UP"];
    m = nan(3,1); sem = m;
    for j = 1:3
        summary = meanSEM(values{j}); m(j)=summary(1); sem(j)=summary(2);
    end
    T = table(repmat(string(group),3,1),repmat(string(control),3,1), ...
        labels,m,sem,'VariableNames', ...
        {'Group','Control','Predictability','MeanAcc','SEMAcc'});
end

function y = local_get_cell(H,P,group,control,pred)
    if group == "Group A", G = H;
    elseif group == "Group B", G = P;
    else, error('Unknown group: %s',group); end
    if control == "Controllable", suffix = '_S1';
    elseif control == "Uncontrollable", suffix = '_S2';
    else, error('Unknown condition: %s',control); end
    y = G.([char(pred),suffix]);
end
