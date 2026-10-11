%% REACTION-TIME REGRESSION COEFFICIENTS: TWO GROUPS x TWO CONDITIONS x TWO PREDICTORS
% Author: Daniyal, University of Melbourne.
%
% PURPOSE: Analyze precomputed participant-level regression coefficients
% for reaction-time models containing accuracy and one model
% regressor (Surprise, Belief Uncertainty or Volatility). This script does
% not fit the participant-level reaction-time regressions.
%
% REQUIREMENTS: MATLAB R2020b or later and Statistics and Machine Learning
% Toolbox. All helpers are included.
%
% INPUT: Twelve Excel files (2 groups x 2 conditions x 3 model regressors).
% Default columns in both groups: Subject, Beta_Cor, Beta_Unc.
% Column mappings are configurable.
% One row per participant. Numeric beta columns may include missing values.
% Subject IDs are required in BOTH groups. Strip only a terminal _S1 or _S2
% suffix, after whitespace trimming and uppercase normalization, to pair
% sessions. IDs such as P001_S1 and P001_S2 become P001. Duplicate normalized
% IDs cause an error. Participants are paired within group and model.
%
%
% STATISTICS PER MODEL: 2 x 2 x 2 design. Group (between) x Condition (within) x Predictor
% (within) mixed repeated-measures ANOVA. Export all ranova p-value variants
% plus the between-group ANOVA. Choose/report sphericity correction separately.
% Bonferroni families match the source:
% A: 4 Welch between-group tests across condition x predictor cells.
% B: 2 paired condition tests separately within each group.
% C: 1 paired accuracy-vs-model test within each group x condition,
%    uncorrected, as in the source. Raw p-values are labelled explicitly.
%
% PLOT: Two panels (accuracy and model regressor), each with four boxes:
% Group A/B in condition 1, then Group A/B in condition 2. Neutral boxes,
% group/condition-colored points, black means +/- SEM. Shared automatic
% symmetric Y-axis by default; optional model-specific manual limits
% and four ticks.
%
% OUTPUT PER MODEL: PNG (600 dpi), vector PDF, TXT and Excel statistics,
% MAT results, matching report and participant-inclusion report.
% Runtime execution against the original data has not been verified here.

clear; clc; close all;

%% USER CONFIGURATION
inputDir = fullfile(pwd,'rt_beta_inputs');
outdir = fullfile(pwd,'rt_beta_outputs');
MODEL_NAMES = ["Surprise","Belief Uncertainty","Volatility"];
MODEL_TOKENS = ["surprise","belief_uncertainty","volatility"];
GROUP_LABELS = ["Group A","Group B"];
GROUP_TOKENS = ["group_a","group_b"];
CONDITION_LABELS = ["Controllable","Uncontrollable"];
% Default filenames, e.g., group_a_surprise_s1.xlsx; edit these as needed.
inputFiles = strings(2,2,3);
for m = 1:3
    for g = 1:2
        for c = 1:2
            inputFiles(g,c,m) = sprintf('%s_%s_s%d.xlsx',GROUP_TOKENS(g),MODEL_TOKENS(m),c);
        end
    end
end
SUBJECT_COLUMN = "Subject";
BETA_COLUMNS = ["Beta_Cor","Beta_Unc";"Beta_Cor","Beta_Unc"]; % Rows: groups A/B.
SHEET = 1;
APPLY_CLEANING = true;
HARD_CAP = 10; % Set Inf to disable magnitude cutoff.
CLEANING_METHOD = "mad"; % "mad" or "sd"; source helper was not supplied.
OUTLIER_THRESHOLD = 3; % Units: scaled MAD or sample SD, respectively.
BALANCE_GROUPS = true;
RANDOM_SEED = 1;
FIXED_Y_AXIS = [false false false]; % Set model 3 true for source volatility limits.
FIXED_Y_LIMITS = [-1 1;-1 1;-0.40 0.34]; % Rows: models.
N_Y_TICKS = 4; % Four shared ticks per model.
png_dpi = 600;
pointColors = [0.10 0.25 0.70;0.65 0.10 0.10; ...
               0.38 0.68 0.95;0.92 0.62 0.62];
assert(isscalar(OUTLIER_THRESHOLD) && isfinite(OUTLIER_THRESHOLD) && OUTLIER_THRESHOLD > 0, ...
    'OUTLIER_THRESHOLD must be a positive finite scalar.');
assert(isscalar(HARD_CAP) && HARD_CAP > 0,'HARD_CAP must be positive or Inf.');
assert(isscalar(CLEANING_METHOD) && ismember(CLEANING_METHOD,["mad","sd"]), ...
    'CLEANING_METHOD must be mad or sd.');
assert(numel(FIXED_Y_AXIS)==3,'FIXED_Y_AXIS must have one flag per model.');
assert(isscalar(N_Y_TICKS) && N_Y_TICKS >= 2 && N_Y_TICKS == floor(N_Y_TICKS), ...
    'N_Y_TICKS must be an integer of at least two.');
if ~isfolder(outdir)
    [ok,msg] = mkdir(outdir);
    if ~ok, error('Cannot create output directory: %s',msg); end
end
% Validate all paths before starting model analyses.
for k = 1:numel(inputFiles)
    file = fullfile(inputDir,inputFiles(k));
    if ~isfile(file), error('Missing input: %s',file); end
end

%% MODEL ANALYSES
for model = 1:3
    modelName = MODEL_NAMES(model);
    token = char(MODEL_TOKENS(model));
    fprintf('\nModel: %s\n',modelName);
    groups = cell(2,1);
    matchingReport = table(GROUP_LABELS(:),zeros(2,1),zeros(2,1),zeros(2,1), ...
        'VariableNames',{'Group','N_S1','N_S2','N_matched'});
    for g = 1:2
        S1 = local_read_beta(fullfile(inputDir,inputFiles(g,1,model)), ...
            SHEET,SUBJECT_COLUMN,BETA_COLUMNS(g,:));
        S2 = local_read_beta(fullfile(inputDir,inputFiles(g,2,model)), ...
            SHEET,SUBJECT_COLUMN,BETA_COLUMNS(g,:));
        [ids,i1,i2] = intersect(S1.id,S2.id,'stable');
        matchingReport.N_S1(g) = numel(S1.id);
        matchingReport.N_S2(g) = numel(S2.id);
        matchingReport.N_matched(g) = numel(ids);
        raw = [S1.beta(i1,:),S2.beta(i2,:)];
        complete = all(isfinite(raw),2);
        magnitudeExcluded = false(numel(ids),1);
        outlier = false(numel(ids),1);
        if APPLY_CLEANING
            magnitudeExcluded = complete & any(abs(raw) > HARD_CAP,2);
            candidates = complete & ~magnitudeExcluded;
            indices = find(candidates);
            cleaned = raw(candidates,:);
            if size(cleaned,1) >= 5
                flagged = local_outlier_rows(cleaned,CLEANING_METHOD,OUTLIER_THRESHOLD);
                outlier(indices(flagged)) = true;
            end
        end
        eligible = complete & ~magnitudeExcluded & ~outlier;
        groups{g} = struct('id',ids,'raw',raw,'complete',complete, ...
            'magnitudeExcluded',magnitudeExcluded,'outlier',outlier, ...
            'eligible',eligible,'retained',false(numel(ids),1));
    end
    eligibleN = cellfun(@(G) sum(G.eligible),groups);
    if any(eligibleN < 2)
        error('Too few participants for %s: Group A=%d, Group B=%d.', ...
            modelName,eligibleN(1),eligibleN(2));
    end
    % Source reset seed per model; plotting uses draws after subsampling.
    rng(RANDOM_SEED,'twister');
    nBalanced = min(eligibleN);
    for g = 1:2
        G = groups{g}; selected = find(G.eligible);
        if BALANCE_GROUPS && numel(selected) > nBalanced
            sampled = sort(randsample(numel(selected),nBalanced,false));
            selected = selected(sampled);
        end
        G.retained(selected) = true;
        G.Y = G.raw(selected,:); G.retainedIDs = G.id(selected);
        groups{g} = G;
    end
    A = groups{1}.Y; B = groups{2}.Y;
    nA = size(A,1); nB = size(B,1);
    fprintf('Eligible: A=%d, B=%d; retained: A=%d, B=%d\n',eligibleN(1),eligibleN(2),nA,nB);
    inclusionReport = table();
    for g = 1:2
        G = groups{g};
        rows = table(repmat(GROUP_LABELS(g),numel(G.id),1),G.id,G.complete, ...
            G.magnitudeExcluded,G.outlier,G.eligible,G.retained,'VariableNames', ...
            {'Group','Subject','Complete_case','Magnitude_excluded','Outlier_excluded','Eligible','Retained'});
        inclusionReport = [inclusionReport;rows];
    end

    %% MIXED ANOVA
    responseNames = {'S1_Acc','S1_ModelReg','S2_Acc','S2_ModelReg'};
    TA = [table("A_"+groups{1}.retainedIDs,categorical(repmat(GROUP_LABELS(1),nA,1)), ...
        'VariableNames',{'Subject','Group'}),array2table(A,'VariableNames',responseNames)];
    TB = [table("B_"+groups{2}.retainedIDs,categorical(repmat(GROUP_LABELS(2),nB,1)), ...
        'VariableNames',{'Subject','Group'}),array2table(B,'VariableNames',responseNames)];
    Tall = [TA;TB];
    within = table(categorical(["S1";"S1";"S2";"S2"]), ...
        categorical(["Acc";"ModelReg";"Acc";"ModelReg"]), ...
        'VariableNames',{'Condition','Predictor'});
    rm = fitrm(Tall,'S1_Acc-S2_ModelReg ~ Group','WithinDesign',within);
    RAN = ranova(rm,'WithinModel','Condition*Predictor');
    ANOVA_between = anova(rm);
    ANOVA_export = addvars(RAN,string(RAN.Properties.RowNames), ...
        'Before',1,'NewVariableNames','Effect');
    ANOVA_export.Properties.RowNames = {};

    %% POSTHOC A: FOUR WELCH GROUP TESTS
    Post_Between = table(string(responseNames(:)),nan(4,1),nan(4,1),nan(4,1),nan(4,1), ...
        'VariableNames',{'Cell','t','df','p_raw','p_bonf'});
    for k = 1:4
        [~,p,~,st] = ttest2(A(:,k),B(:,k),'Vartype','unequal');
        Post_Between.t(k)=st.tstat; Post_Between.df(k)=st.df; Post_Between.p_raw(k)=p;
    end
    Post_Between.p_bonf = min(Post_Between.p_raw*4,1);

    %% POSTHOC B: TWO PAIRED CONDITION TESTS PER GROUP
    predictors = ["Accuracy";modelName];
    Post_Condition = table(repelem(GROUP_LABELS(:),2),repmat(predictors,2,1), ...
        nan(4,1),nan(4,1),nan(4,1),nan(4,1),'VariableNames', ...
        {'Group','Predictor','t','df','p_raw','p_bonf'});
    for g = 1:2
        Y = groups{g}.Y;
        for k = 1:2
            row = (g-1)*2+k;
            [~,p,~,st] = ttest(Y(:,k),Y(:,k+2));
            Post_Condition.t(row)=st.tstat; Post_Condition.df(row)=st.df;
            Post_Condition.p_raw(row)=p;
        end
        rows = (g-1)*2+(1:2);
        Post_Condition.p_bonf(rows) = min(Post_Condition.p_raw(rows)*2,1);
    end

    %% POSTHOC C: ONE UNCORRECTED PAIRED TEST PER GROUP/CONDITION
    Post_Predictor = table(strings(4,1),strings(4,1),strings(4,1), ...
        nan(4,1),nan(4,1),nan(4,1),'VariableNames', ...
        {'Group','Condition','Comparison','t','df','p_raw'});
    for g = 1:2
        Y = groups{g}.Y;
        for c = 1:2
            row = (g-1)*2+c; offset = (c-1)*2;
            [~,p,~,st] = ttest(Y(:,offset+1),Y(:,offset+2));
            Post_Predictor.Group(row)=GROUP_LABELS(g);
            Post_Predictor.Condition(row)=CONDITION_LABELS(c);
            Post_Predictor.Comparison(row)=predictors(1)+" vs "+predictors(2);
            Post_Predictor.t(row)=st.tstat; Post_Predictor.df(row)=st.df;
            Post_Predictor.p_raw(row)=p;
        end
    end

    %% DESCRIPTIVES
    descriptives = table();
    for g = 1:2
        Y = groups{g}.Y; n = size(Y,1);
        rows = table(repmat(GROUP_LABELS(g),4,1),repelem(CONDITION_LABELS(:),2), ...
            repmat(predictors,2,1),repmat(n,4,1),mean(Y,1)',std(Y,0,1)'/sqrt(n), ...
            'VariableNames',{'Group','Condition','Predictor','N','Mean','SEM'});
        descriptives = [descriptives;rows];
    end

    %% TWO-PANEL FIGURE
    fig = local_plot_betas(A,B,predictors,GROUP_LABELS,CONDITION_LABELS, ...
        pointColors,FIXED_Y_AXIS(model),FIXED_Y_LIMITS(model,:),N_Y_TICKS);
    fig_png = fullfile(outdir,sprintf('RT_Betas_%s.png',token));
    fig_pdf = fullfile(outdir,sprintf('RT_Betas_%s_vector.pdf',token));
    exportgraphics(fig,fig_png,'Resolution',png_dpi);
    exportgraphics(fig,fig_pdf,'ContentType','vector');

    %% SAVE STATISTICS AND AUDIT REPORTS
    stats_xlsx = fullfile(outdir,sprintf('RT_Beta_Statistics_%s.xlsx',token));
    writetable(ANOVA_export,stats_xlsx,'Sheet','ANOVA_2x2x2');
    writetable(ANOVA_between,stats_xlsx,'Sheet','ANOVA_between','WriteRowNames',true);
    writetable(Post_Between,stats_xlsx,'Sheet','Posthoc_BetweenGroup');
    writetable(Post_Condition,stats_xlsx,'Sheet','Posthoc_Condition');
    writetable(Post_Predictor,stats_xlsx,'Sheet','Posthoc_PredictorPairs');
    writetable(descriptives,stats_xlsx,'Sheet','Descriptives');
    writetable(matchingReport,stats_xlsx,'Sheet','Matching_report');
    writetable(inclusionReport,stats_xlsx,'Sheet','Inclusion_report');
    stats_txt = fullfile(outdir,sprintf('RT_Beta_Statistics_%s.txt',token));
    fid = fopen(stats_txt,'w');
    if fid < 0, error('Cannot write statistics text file: %s',stats_txt); end
    fprintf(fid,'Model: %s\nCleaning=%d; method=%s; threshold=%g; hard cap=%g; balance=%d; seed=%d\n', ...
        modelName,APPLY_CLEANING,CLEANING_METHOD,OUTLIER_THRESHOLD,HARD_CAP,BALANCE_GROUPS,RANDOM_SEED);
    fprintf(fid,'Retained N: Group A=%d; Group B=%d\n\n',nA,nB);
    fprintf(fid,'Repeated-measures ANOVA\n%s\n',evalc('disp(RAN)'));
    fprintf(fid,'Between-group ANOVA\n%s\n',evalc('disp(ANOVA_between)'));
    fprintf(fid,'Between groups: Bonferroni x4\n%s\n',evalc('disp(Post_Between)'));
    fprintf(fid,'Conditions: Bonferroni x2 per group\n%s\n',evalc('disp(Post_Condition)'));
    fprintf(fid,'Accuracy vs model regressor: uncorrected paired tests\n%s\n',evalc('disp(Post_Predictor')));
    fclose(fid);
    save(fullfile(outdir,sprintf('RT_Beta_Outputs_%s.mat',token)), ...
        'modelName','model','groups','Tall','within','rm','RAN','ANOVA_export', ...
        'ANOVA_between','Post_Between','Post_Condition','Post_Predictor', ...
        'descriptives','matchingReport','inclusionReport','inputDir','inputFiles', ...
        'SUBJECT_COLUMN','BETA_COLUMNS','SHEET','APPLY_CLEANING','CLEANING_METHOD','OUTLIER_THRESHOLD','HARD_CAP', ...
        'BALANCE_GROUPS','RANDOM_SEED','FIXED_Y_AXIS','FIXED_Y_LIMITS','N_Y_TICKS','fig_png','fig_pdf');
    fprintf('Saved model figures and statistics: %s\n',modelName);
end
fprintf('\nCompleted all three models. Output: %s\n',outdir);

%% LOCAL HELPERS
function S = local_read_beta(file,sheet,subjectColumn,betaColumns)
    T = readtable(file,'Sheet',sheet,'VariableNamingRule','preserve');
    required = [subjectColumn,betaColumns];
    if ~all(ismember(required,string(T.Properties.VariableNames)))
        error('Required columns missing in %s: %s',file,strjoin(required,', '));
    end
    ids = upper(strtrim(string(T.(char(subjectColumn)))));
    ids = regexprep(ids,'_S[12]$','');
    if any(ismissing(ids) | ids == "") || numel(unique(ids)) ~= numel(ids)
        error('Empty or duplicate normalized participant IDs in %s.',file);
    end
    beta = nan(height(T),2);
    for k = 1:2
        raw = T.(char(betaColumns(k)));
        if isnumeric(raw)
            values = double(raw);
        else
            text = strtrim(string(raw)); values = str2double(text);
            bad = ~ismissing(text) & text ~= "" & isnan(values) & lower(text) ~= "nan";
            if any(bad), error('Nonnumeric beta in %s, column %s.',file,betaColumns(k)); end
        end
        beta(:,k) = values(:);
    end
    S = struct('id',ids(:),'beta',beta);
end

function fig = local_plot_betas(A,B,predictors,groupLabels,conditionLabels,colors,fixedAxis,fixedLimits,nTicks)
    values = [A(:);B(:)];
    if fixedAxis
        if numel(fixedLimits) ~= 2 || any(~isfinite(fixedLimits)) || fixedLimits(1) >= fixedLimits(2)
            error('FIXED_Y_LIMITS must contain two ascending finite limits.');
        end
        if min(values) < fixedLimits(1) || max(values) > fixedLimits(2)
            error('Fixed beta Y-axis would clip retained values; use automatic limits.');
        end
        limits = fixedLimits;
    else
        largest = max(abs(values));
        if largest == 0, largest = 1; end
        largest = largest*1.06;
        limits = [-largest largest];
    end
    ticks = linspace(limits(1),limits(2),nTicks);
    fig = figure('Color','w','Units','pixels','Position',[100 100 1400 700]);
    tl = tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
    x = [1 2 3.5 4.5];
    for p = 1:2
        ax = nexttile(tl); hold(ax,'on');
        data = {A(:,p),B(:,p),A(:,p+2),B(:,p+2)};
        for k = 1:4
            y = data{k};
            boxchart(ax,x(k)*ones(size(y)),y,'BoxFaceColor',[0.68 0.68 0.68], ...
                'BoxFaceAlpha',0.35,'BoxWidth',0.42,'LineWidth',1.4,'MarkerStyle','none');
            jitter = (rand(numel(y),1)-0.5)*2*0.16;
            scatter(ax,x(k)+jitter,y,44,colors(k,:),'filled','MarkerEdgeColor','k');
            mu = mean(y); sem = std(y)/sqrt(numel(y));
            errorbar(ax,x(k),mu,sem,'k','LineWidth',1.5,'CapSize',8);
            scatter(ax,x(k),mu,95,'k','filled');
        end
        xlim(ax,[0.5 5]); ylim(ax,limits); ax.YTick = ticks;
        ytickformat(ax,'%.3g');
        ax.XTick = [1.5 4]; ax.XTickLabel = cellstr(conditionLabels);
        ax.FontSize = 20; ax.LineWidth = 1.6; ax.TickDir = 'out'; ax.Box = 'off';
        title(ax,predictors(p),'FontSize',24,'FontWeight','bold');
        yline(ax,0,':','Color',[0.5 0.5 0.5],'HandleVisibility','off');
        if p == 1
            ylabel(ax,'\beta','FontSize',30,'FontWeight','bold');
        else
            ax.YTickLabel = []; ax.YColor = 'none';
        end
        if p == 2
            handles = gobjects(4,1);
            for k = 1:4
                handles(k) = scatter(ax,nan,nan,70,colors(k,:),'filled','MarkerEdgeColor','k');
            end
            labels = [groupLabels(1)+" ("+conditionLabels(1)+")", ...
                      groupLabels(2)+" ("+conditionLabels(1)+")", ...
                      groupLabels(1)+" ("+conditionLabels(2)+")", ...
                      groupLabels(2)+" ("+conditionLabels(2)+")"];
            lgd = legend(ax,handles,cellstr(labels),'Orientation','horizontal', ...
                'Box','off','FontSize',16);
            lgd.Layout.Tile = 'north'; lgd.AutoUpdate = 'off';
        end
    end
end

function flagged = local_outlier_rows(Y,method,threshold)
    if method == "mad"
        center = median(Y,1);
        spread = 1.4826*median(abs(Y-center),1);
    else
        center = mean(Y,1);
        spread = std(Y,0,1);
    end
    deviations = abs(Y-center);
    tolerance = 10*eps(max(1,abs(center)));
    limits = threshold*spread;
    zeroSpread = spread <= tolerance;
    limits(zeroSpread) = tolerance(zeroSpread);
    flagged = any(deviations > limits,2);
end
