%% RATING REGRESSION COEFFICIENTS: TWO GROUPS x TWO CONDITIONS x THREE PREDICTORS

% PURPOSE: Analyze precomputed participant-level regression coefficients
% for rating models containing previous rating, accuracy and one model
% regressor (Surprise, Belief Uncertainty or Volatility). This script does
% not fit the participant-level rating regressions.
%
% REQUIREMENTS: MATLAB R2020b or later and Statistics and Machine Learning
% Toolbox. All helpers are included.
%
% INPUT: Twelve Excel files (2 groups x 2 conditions x 3 model regressors).
% Default columns: Subject, Beta_SR_prev, Beta_Accuracy, Beta_U.
% One row per participant. Numeric beta columns may include missing values.
% Subject IDs are required in BOTH groups. Strip only a terminal _S1 or _S2
% suffix, after whitespace trimming and uppercase normalization, to pair
% sessions. IDs such as P001_S1 and P001_S2 become P001. Duplicate normalized
% IDs cause an error. Participants are paired within group and model.
%
% PREPROCESSING: Complete-case selection across six coefficients precedes
% optional outlier removal. Within each group/model, calculate a single-pass
% column-wise z score from sample means and SDs; remove a participant if ANY
% of their six values exceeds SD_THRESHOLD. 
%
% STATISTICS PER MODEL: Group (between) x Condition (within) x Predictor
% (within) mixed repeated-measures ANOVA. Export all ranova p-value variants
% plus the between-group ANOVA. Choose/report sphericity correction separately.
% Bonferroni families match the source:
% A: 6 Welch between-group tests across condition x predictor cells.
% B: 3 paired condition tests separately within each group.
% C: 3 paired predictor tests separately within each group x condition.

%
% PLOT: Three panels (previous rating, accuracy, model regressor), each with
% four boxes: Group A/B in condition 1, then Group A/B in condition 2.
% Neutral boxes, group/condition-colored points, black means +/- SEM.
% Shared symmetric Y-axis with exactly five ticks per model. 

% OUTPUT PER MODEL: PNG (600 dpi), vector PDF, TXT and Excel statistics,
% MAT results, matching report and participant-inclusion report.
% Runtime execution against the original data has not been verified here.
% Author: Daniyal Rajput, University of Melbourne. Written by the author.

clear; clc; close all;

%% USER CONFIGURATION
inputDir = fullfile(pwd,'rating_beta_inputs');
outdir = fullfile(pwd,'rating_beta_outputs');
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
BETA_COLUMNS = ["Beta_SR_prev","Beta_Accuracy","Beta_U"];
SHEET = 1;
APPLY_3SD = true;
SD_THRESHOLD = 3;
BALANCE_GROUPS = true;
RANDOM_SEED = 1;
FIXED_Y_AXIS = false;
FIXED_Y_LIMITS = [-0.5 1];
png_dpi = 600;
pointColors = [0.10 0.25 0.70;0.65 0.10 0.10; ...
               0.38 0.68 0.95;0.92 0.62 0.62];
assert(isfinite(SD_THRESHOLD) && SD_THRESHOLD > 0,'SD_THRESHOLD must be positive.');
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
            SHEET,SUBJECT_COLUMN,BETA_COLUMNS);
        S2 = local_read_beta(fullfile(inputDir,inputFiles(g,2,model)), ...
            SHEET,SUBJECT_COLUMN,BETA_COLUMNS);
        [ids,i1,i2] = intersect(S1.id,S2.id,'stable');
        matchingReport.N_S1(g) = numel(S1.id);
        matchingReport.N_S2(g) = numel(S2.id);
        matchingReport.N_matched(g) = numel(ids);
        raw = [S1.beta(i1,:),S2.beta(i2,:)];
        complete = all(isfinite(raw),2);
        outlier = false(numel(ids),1);
        cleaned = raw(complete,:);
        if APPLY_3SD && size(cleaned,1) >= 5
            mu = mean(cleaned,1); sd = std(cleaned,0,1); sd(sd < eps) = eps;
            flagged = any(abs((cleaned-mu)./sd) > SD_THRESHOLD,2);
            completeIndices = find(complete);
            outlier(completeIndices(flagged)) = true;
        end
        eligible = complete & ~outlier;
        groups{g} = struct('id',ids,'raw',raw,'complete',complete, ...
            'outlier',outlier,'eligible',eligible,'retained',false(numel(ids),1));
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
            G.outlier,G.eligible,G.retained,'VariableNames', ...
            {'Group','Subject','Complete_case','Outlier_excluded','Eligible','Retained'});
        inclusionReport = [inclusionReport;rows];
    end

    %% MIXED ANOVA
    responseNames = {'S1_Prev','S1_Acc','S1_ModelReg','S2_Prev','S2_Acc','S2_ModelReg'};
    TA = [table("A_"+groups{1}.retainedIDs,categorical(repmat(GROUP_LABELS(1),nA,1)), ...
        'VariableNames',{'Subject','Group'}),array2table(A,'VariableNames',responseNames)];
    TB = [table("B_"+groups{2}.retainedIDs,categorical(repmat(GROUP_LABELS(2),nB,1)), ...
        'VariableNames',{'Subject','Group'}),array2table(B,'VariableNames',responseNames)];
    Tall = [TA;TB];
    within = table(categorical(["S1";"S1";"S1";"S2";"S2";"S2"]), ...
        categorical(["Prev";"Acc";"ModelReg";"Prev";"Acc";"ModelReg"]), ...
        'VariableNames',{'Condition','Predictor'});
    rm = fitrm(Tall,'S1_Prev-S2_ModelReg ~ Group','WithinDesign',within);
    RAN = ranova(rm,'WithinModel','Condition*Predictor');
    ANOVA_between = anova(rm);
    ANOVA_export = addvars(RAN,string(RAN.Properties.RowNames), ...
        'Before',1,'NewVariableNames','Effect');
    ANOVA_export.Properties.RowNames = {};

    %% POSTHOC A: SIX WELCH GROUP TESTS
    Post_Between = table(string(responseNames(:)),nan(6,1),nan(6,1),nan(6,1),nan(6,1), ...
        'VariableNames',{'Cell','t','df','p_raw','p_bonf'});
    for k = 1:6
        [~,p,~,st] = ttest2(A(:,k),B(:,k),'Vartype','unequal');
        Post_Between.t(k)=st.tstat; Post_Between.df(k)=st.df; Post_Between.p_raw(k)=p;
    end
    Post_Between.p_bonf = min(Post_Between.p_raw*6,1);

    %% POSTHOC B: THREE PAIRED CONDITION TESTS PER GROUP
    predictors = ["Previous rating";"Accuracy";modelName];
    Post_Condition = table(repelem(GROUP_LABELS(:),3),repmat(predictors,2,1), ...
        nan(6,1),nan(6,1),nan(6,1),nan(6,1),'VariableNames', ...
        {'Group','Predictor','t','df','p_raw','p_bonf'});
    for g = 1:2
        Y = groups{g}.Y;
        for k = 1:3
            row = (g-1)*3+k;
            [~,p,~,st] = ttest(Y(:,k),Y(:,k+3));
            Post_Condition.t(row)=st.tstat; Post_Condition.df(row)=st.df;
            Post_Condition.p_raw(row)=p;
        end
        rows = (g-1)*3+(1:3);
        Post_Condition.p_bonf(rows) = min(Post_Condition.p_raw(rows)*3,1);
    end

    %% POSTHOC C: THREE PAIRED PREDICTOR COMPARISONS PER GROUP/CONDITION
    pairs = [1 2;1 3;2 3];
    Post_Predictor = table(strings(12,1),strings(12,1),strings(12,1), ...
        nan(12,1),nan(12,1),nan(12,1),nan(12,1),'VariableNames', ...
        {'Group','Condition','Comparison','t','df','p_raw','p_bonf'});
    row = 0;
    for g = 1:2
        Y = groups{g}.Y;
        for c = 1:2
            for k = 1:3
                row = row+1; offset = (c-1)*3;
                [~,p,~,st] = ttest(Y(:,offset+pairs(k,1)),Y(:,offset+pairs(k,2)));
                Post_Predictor.Group(row)=GROUP_LABELS(g);
                Post_Predictor.Condition(row)=CONDITION_LABELS(c);
                Post_Predictor.Comparison(row)=predictors(pairs(k,1))+" vs "+predictors(pairs(k,2));
                Post_Predictor.t(row)=st.tstat; Post_Predictor.df(row)=st.df;
                Post_Predictor.p_raw(row)=p;
            end
            rows = row-2:row;
            Post_Predictor.p_bonf(rows)=min(Post_Predictor.p_raw(rows)*3,1);
        end
    end

    %% DESCRIPTIVES
    descriptives = table();
    for g = 1:2
        Y = groups{g}.Y; n = size(Y,1);
        rows = table(repmat(GROUP_LABELS(g),6,1),repelem(CONDITION_LABELS(:),3), ...
            repmat(predictors,2,1),repmat(n,6,1),mean(Y,1)',std(Y,0,1)'/sqrt(n), ...
            'VariableNames',{'Group','Condition','Predictor','N','Mean','SEM'});
        descriptives = [descriptives;rows];
    end

    %% THREE-PANEL FIGURE
    fig = local_plot_betas(A,B,predictors,GROUP_LABELS,CONDITION_LABELS, ...
        pointColors,FIXED_Y_AXIS,FIXED_Y_LIMITS);
    fig_png = fullfile(outdir,sprintf('Rating_Betas_%s.png',token));
    fig_pdf = fullfile(outdir,sprintf('Rating_Betas_%s_vector.pdf',token));
    exportgraphics(fig,fig_png,'Resolution',png_dpi);
    exportgraphics(fig,fig_pdf,'ContentType','vector');

    %% SAVE STATISTICS AND AUDIT REPORTS
    stats_xlsx = fullfile(outdir,sprintf('Rating_Beta_Statistics_%s.xlsx',token));
    writetable(ANOVA_export,stats_xlsx,'Sheet','ANOVA_2x2x3');
    writetable(ANOVA_between,stats_xlsx,'Sheet','ANOVA_between','WriteRowNames',true);
    writetable(Post_Between,stats_xlsx,'Sheet','Posthoc_BetweenGroup');
    writetable(Post_Condition,stats_xlsx,'Sheet','Posthoc_Condition');
    writetable(Post_Predictor,stats_xlsx,'Sheet','Posthoc_PredictorPairs');
    writetable(descriptives,stats_xlsx,'Sheet','Descriptives');
    writetable(matchingReport,stats_xlsx,'Sheet','Matching_report');
    writetable(inclusionReport,stats_xlsx,'Sheet','Inclusion_report');
    stats_txt = fullfile(outdir,sprintf('Rating_Beta_Statistics_%s.txt',token));
    fid = fopen(stats_txt,'w');
    if fid < 0, error('Cannot write statistics text file: %s',stats_txt); end
    fprintf(fid,'Model: %s\n3SD=%d; threshold=%g; balance=%d; seed=%d\n', ...
        modelName,APPLY_3SD,SD_THRESHOLD,BALANCE_GROUPS,RANDOM_SEED);
    fprintf(fid,'Retained N: Group A=%d; Group B=%d\n\n',nA,nB);
    fprintf(fid,'Repeated-measures ANOVA\n%s\n',evalc('disp(RAN)'));
    fprintf(fid,'Between-group ANOVA\n%s\n',evalc('disp(ANOVA_between)'));
    fprintf(fid,'Between groups: Bonferroni x6\n%s\n',evalc('disp(Post_Between)'));
    fprintf(fid,'Conditions: Bonferroni x3 per group\n%s\n',evalc('disp(Post_Condition)'));
    fprintf(fid,'Predictors: Bonferroni x3 per group/condition\n%s\n',evalc('disp(Post_Predictor)'));
    fclose(fid);
    save(fullfile(outdir,sprintf('Rating_Beta_Outputs_%s.mat',token)), ...
        'modelName','model','groups','Tall','within','rm','RAN','ANOVA_export', ...
        'ANOVA_between','Post_Between','Post_Condition','Post_Predictor', ...
        'descriptives','matchingReport','inclusionReport','inputDir','inputFiles', ...
        'SUBJECT_COLUMN','BETA_COLUMNS','SHEET','APPLY_3SD','SD_THRESHOLD', ...
        'BALANCE_GROUPS','RANDOM_SEED','fig_png','fig_pdf');
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
    beta = nan(height(T),3);
    for k = 1:3
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

function fig = local_plot_betas(A,B,predictors,groupLabels,conditionLabels,colors,fixedAxis,fixedLimits)
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
    ticks = linspace(limits(1),limits(2),5);
    fig = figure('Color','w','Units','pixels','Position',[100 100 1800 700]);
    tl = tiledlayout(1,3,'TileSpacing','compact','Padding','compact');
    x = [1 2 3.5 4.5];
    for p = 1:3
        ax = nexttile(tl); hold(ax,'on');
        data = {A(:,p),B(:,p),A(:,p+3),B(:,p+3)};
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
        if p == 3
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
