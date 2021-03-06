function varargout = simulate(this, inputDb, baseRange, varargin)
% simulate  Simulate model
%{
%
% ## Syntax ##
%
%     [outputDb, outputInfo] = simulate(model, inputDb, range, ...)
%
%
% Input Arguments
%-----------------
%
%
% __`model`__ [ Model ]
% > 
% Model object with a valid solution avalaible for each of its parameter variants.
%
%
% __`inputDb`__ [ struct | Dictionary ]
% >
% Databank (struct or Dictionary) with initial conditions, shocks, and
% exogenized data points for the simulation.
%
%
% __`range`__ [ DateWrapper | numeric ]
% >
% Simulation range; only the start date (the first element in `range`) and
% the end date (the last element in `range`) are considered.
%
%
% Output Arguments
%------------------
%
% __`outputDb`__ [ struct | Dictionary ]
% >
% Databank (struct or Dictionary) with the simulation results; if options
% `PrependInput=` or `AppendInput=` are not used, the time series in
% `outputDb` span the simulation `range` plus all necessary initial
% conditions for those variables that have lags in the model.
%
%
% ## Options ##
%
%
% ## Description ##
%
%
% ## Example ##
%
%
%}

% -[IrisToolbox] for Macroeconomic Modeling
% -Copyright (c) 2007-2020 IRIS Solutions Team

TYPE = @int8;

persistent pp
if isempty(pp)
    pp = extend.InputParser('model.simulate');
    %
    % Required input arguments
    %
    addRequired(pp, 'solvedModel', @validate.solvedModel);
    addRequired(pp, 'inputDb', @(x) validate.databank(x) || isa(x, 'simulate.Data') || isequal(x, "asynchronous"));
    addRequired(pp, 'simulationRange', @(x) DateWrapper.validateProperRangeInput(x) || isequal(x, @auto));
    %
    % Options
    %
    pp.addDeviationOptions(false);
    addParameter(pp, 'Anticipate', true, @validate.logicalScalar);
    addParameter(pp, {'AppendPostsample', 'AppendInput'}, false, @validate.logicalScalar);
    addParameter(pp, {'AppendPresample', 'PrependInput'}, false, @validate.logicalScalar);
    addParameter(pp, 'Contributions', false, @validate.logicalScalar);
    addParameter(pp, 'IgnoreShocks', false, @validate.logicalScalar);
    addParameter(pp, 'Method', solver.Method.FIRST_ORDER, @solver.Method.validate);
    addParameter(pp, 'OutputData', 'Databank', @(x) validateString(x, {'Databank', 'simulate.Data'}));
    addParameter(pp, 'OutputType', 'struct', @validate.databankType);
    addParameter(pp, 'Plan', true, @(x) validate.logicalScalar(x) || isa(x, 'Plan'));
    addParameter(pp, 'ProgressInfo', false, @validate.logicalScalar);
    addParameter(pp, 'SuccessOnly', false, @validate.logicalScalar);
    addParameter(pp, 'Solver', @auto, @validateSolver);
    addParameter(pp, 'SparseShocks', false, @validate.logicalScalar)
    addParameter(pp, 'SystemProperty', false, @(x) isequal(x, false) || validate.list(x));
    addParameter(pp, 'Window', @auto, @(x) isequal(x, @auto) || isequal(x, @max) || (isnumeric(x) && isscalar(x) && x==round(x) && x>=1));

    addParameter(pp, 'Initial', 'Data', @(x) validate.anyString(x, 'Data', 'FirstOrder'));
    addParameter(pp, 'PrepareGradient', true, @validate.logicalScalar);
end
parse(pp, this, inputDb, baseRange, varargin{:});
opt = pp.Options;
opt.EvalTrends = opt.DTrends;
usingDefaults = pp.UsingDefaultsInStruct;

if ~isequal(baseRange, @auto)
    baseRange = double(baseRange);
end
[opt.Window, baseRange] = parseWindowOptionAndBaseRange(opt.Window, opt.Method, baseRange);
opt.Method = solver.Method.parse(opt.Method);
opt.Solver = parseSolverOption(opt.Solver, opt.Method);
isAsynchronous = isequal(inputDb, "asynchronous");
opt.Solver = hereResolveSolverOption(opt.Solver);

%--------------------------------------------------------------------------

nv = length(this);

% Check the input databank; treat all names as optional, and check for
% missing initial conditions later
requiredNames = cell.empty(1, 0);
optionalNames = this.Quantity.Name;
databankInfo = checkInputDatabank(this, inputDb, baseRange, requiredNames, optionalNames);

hereResolveOptionConflicts( );
plan = opt.Plan;

%
% Prepare running data
%
runningData = simulate.InputOutputData( );
runningData.IsAsynchronous = isAsynchronous;
runningData.PrepareOutputInfo = nargout>=2;

% Retrieve data from intput databank, set up ranges
herePrepareData( );

hereCopyOptionsToRunningData( );

if opt.Contributions
    % Expand and set up YXEPG to prepare contributions simulation
    herePrepareContributions( );
end

% Define time frames; can be done only after we expand the data for
% contributions
herePrepareTimeFrames( );

% Check initial conditions for NaNs
hereCheckInitialConditions( );

herePrepareBlazer( );

systemProperty = hereSetupSystemProperty( );

if ~isequal(opt.SystemProperty, false)
    varargout{1} = systemProperty;
    return
end

progressInfo = ProgressInfo.empty(0);
if opt.ProgressInfo
    progressInfo = herePrepareProgressInfo( );
end


% /////////////////////////////////////////////////////////////////////////
numRuns = runningData.NumOfPages;
for i = 1 : numRuns
    simulateTimeFrames(this, systemProperty, i);
    if opt.ProgressInfo
        hereUpdateProgressInfo(i);
    end
end
if opt.ProgressInfo
    complete(progressInfo);
end
% /////////////////////////////////////////////////////////////////////////


if opt.Contributions
    herePostprocessContributions( );
end

if isAsynchronous
    return
end

outputDb = hereCreateOutputData( );
outputInfo = herePrepareOutputInfo( );


%<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
varargout = { outputDb, outputInfo };
%<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

return
    



    function hereResolveOptionConflicts( )
        if ~usingDefaults.Anticipate && ~usingDefaults.Plan
            thisError = { 'Model:CannotUseAnticipateAndPlan'
                          'Options Anticipate= and Plan= cannot be combined in one simulate(~)' };
            throw(exception.Base(thisError, 'error'));
        end
        if ~usingDefaults.Anticipate && usingDefaults.Plan
            opt.Plan = opt.Anticipate;
        end
        if ~isa(opt.Plan, 'Plan')
            opt.Plan = Plan(this, baseRange, 'Anticipate=', opt.Plan);
        else
            checkCompatibilityOfPlan(this, baseRange, opt.Plan);
        end
        if opt.Contributions && opt.Plan.NumOfExogenizedPoints>0
            thisError = { 'Model:CannotEvalContributionsWithExogenized'
                          'Option Contributions=true cannot be used in simulations with exogenized variables' }
            throw(exception.Base(thisError, 'error'));
        end
        if opt.Contributions && databankInfo.NumOfPages>1
            thisError = { 'Model:CannotEvalContributionsWithMultipleDataSets'
                          'Option Contributions=true cannot be used in simulations on multiple data sets' }
            throw(exception.Base(thisError, 'error'));
        end
    end%




    function hereCopyOptionsToRunningData( )
        numRuns = runningData.NumOfPages;
        runningData.Plan = plan;
        runningData.Initial = opt.Initial;
        runningData.Window = opt.Window;
        runnintDaga.SuccessOnly = opt.SuccessOnly;
        runningData.SparseShocks = opt.SparseShocks;
        runningData.SolverOptions = opt.Solver;
        runningData.Method = repmat(opt.Method, 1, numRuns);
        runningData.Deviation = repmat(opt.Deviation, 1, numRuns);
        runningData.NeedsEvalTrends = repmat(opt.EvalTrends, 1, numRuns);
    end%




    function herePrepareData( )
        numDummyPeriods = hereCalculateNumOfDummyPeriods( );
        startOfBaseRange = baseRange(1);
        endOfBaseRange = baseRange(end);
        endOfBaseRangePlusDummy = endOfBaseRange + numDummyPeriods;
        baseRangePlusDummy = [startOfBaseRange, endOfBaseRangePlusDummy];
        [ runningData.YXEPG, ~, ...
          extendedRange, ~, ...
          runningData.MaxShift, ...
          runningData.TimeTrend ] = data4lhsmrhs( this, ...
                                                  inputDb, ...
                                                  baseRangePlusDummy, ...
                                                  'ResetShocks=', true, ...
                                                  'IgnoreShocks=', opt.IgnoreShocks, ...
                                                  'NumOfDummyPeriods', numDummyPeriods );
        startOfExtendedRange = extendedRange(1);
        endOfExtendedRange = extendedRange(end);
        runningData.ExtendedRange = [startOfExtendedRange, endOfExtendedRange];
        runningData.BaseRangeColumns = colon( round(startOfBaseRange - startOfExtendedRange + 1), ...
                                              round(endOfBaseRange - startOfExtendedRange + 1) );
        numPages = runningData.NumOfPages;
        if numPages==1 && nv>1
            % Expand number of data sets to match number of parameter variants
            runningData.YXEPG = repmat(runningData.YXEPG, 1, 1, nv);
        end
        numRuns = runningData.NumOfPages;
        runningData.InxOfInitInPresample = getInxOfInitInPresample(this, runningData.BaseRangeColumns(1));
        runningData.Method = repmat(opt.Method, 1, numRuns);
        runningData.Deviation = repmat(opt.Deviation, 1, numRuns);
        runningData.NeedsEvalTrends = repmat(opt.EvalTrends, 1, numRuns);
    end%




    function herePrepareContributions( )
        firstColumnToSimulate = runningData.BaseRangeColumns(1);
        inxLog = this.Quantity.InxOfLog;
        inxE = getIndexByType(this, TYPE(31), TYPE(32));
        posE = find(inxE);
        numE = nnz(inxE);
        numRuns = numE + 2;
        runningData.YXEPG = repmat(runningData.YXEPG, 1, 1, numRuns);
        % Zero out initial conditions in shock contributions
        runningData.YXEPG(inxLog, 1:firstColumnToSimulate-1, 1:numE) = 1;
        runningData.YXEPG(~inxLog, 1:firstColumnToSimulate-1, 1:numE) = 0;
        for ii = 1 : numE
            temp = runningData.YXEPG(posE(ii), :, ii);
            runningData.YXEPG(inxE, :, ii) = 0;
            runningData.YXEPG(posE(ii), :, ii) = temp;
        end
        % Zero out all shocks in init+const contributions
        runningData.YXEPG(inxE, firstColumnToSimulate:end, end-1) = 0;

        if opt.Method==solver.Method.FIRST_ORDER 
            % Assign zero contributions of nonlinearities right away if
            % this is a first order simulation
            runningData.YXEPG(inxLog, :, end) = 1;
            runningData.YXEPG(~inxLog, :, end) = 0;
        end

        runningData.Method = repmat(solver.Method.FIRST_ORDER, 1, numRuns);
        if opt.Method==solver.Method.FIRST_ORDER 
            % Assign zero contributions of nonlinearities right away if
            % this is a first order simulation
            runningData.Method(end) = solver.Method.NONE;
        else
            runningData.Method(end) = opt.Method;
        end
        runningData.Deviation = true(1, numRuns);
        runningData.Deviation(end-1:end) = opt.Deviation;
        runningData.NeedsEvalTrends = false(1, numRuns);
        runningData.NeedsEvalTrends(end-1:end) = opt.EvalTrends;
    end%




    function timeFrameDates = herePrepareTimeFrames( )
        numPages = runningData.NumOfPages;
        inxE = getIndexByType(this.Quantity, TYPE(31), TYPE(32));
        runningData.TimeFrames = cell(1, numPages);
        runningData.MixinUnanticipated = false(1, numPages);
        runningData.TimeFrameDates = cell(1, numPages);
        extendedRange = runningData.ExtendedRange;
        startExtendedRange = extendedRange(1);
        deficiency = cell(1, numPages);
        covariance = cell(1, numPages);
        for page = 1 : numPages
            [~, unanticipatedE] = simulate.Data.splitE( runningData.YXEPG(inxE, :, page), ...
                                                        plan.AnticipationStatusOfExogenous, ...
                                                        runningData.BaseRangeColumns );
            [ runningData.TimeFrames{page}, ...
              runningData.MixinUnanticipated(page) ] = ...
                hereSplitIntoTimeFrames( unanticipatedE, ...
                                         runningData.BaseRangeColumns, ...
                                         plan, ...
                                         runningData.MaxShift, ...
                                         opt );
            numTimeFrames = size(runningData.TimeFrames{page}, 1);
            timeFrameDates = nan(numTimeFrames, 2);
            deficiency{page} = zeros(1, numTimeFrames);
            covariance{page} = cell(1, numTimeFrames);
            for frame = 1 : numTimeFrames
                startOfTimeFrame = startExtendedRange + runningData.TimeFrames{page}(frame, 1) - 1;
                endOfTimeFrame = startExtendedRange + runningData.TimeFrames{page}(frame, end) - 1;
                timeFrameDates(frame, :) = [startOfTimeFrame, endOfTimeFrame];
                %
                % Check determinacy of simulation plan within this time frame
                % Determine covariance matrix for underdetermined systems
                %
                [deficiency{page}(frame), covariance{page}{frame}] = hereCheckDeterminacyOfPlan( );
            end
            runningData.TimeFrameDates{page} = DateWrapper(timeFrameDates);
        end
        if nnz([deficiency{:}])>0
            hereReportDeficiencyOfPlan( );
        end

        return

            function [deficiency, covariance] = hereCheckDeterminacyOfPlan( )
                %
                % Check determinacy of plan in each
                firstColumnOfTimeFrame = runningData.TimeFrames{page}(frame, 1);
                lastColumnOfSimulation = runningData.BaseRangeColumns(end);
                [ inxExogenized, ...
                  inxEndogenized ] = getSwapsWithinTimeFrame( plan, ...
                                                              firstColumnOfTimeFrame, ...
                                                              lastColumnOfSimulation );
                numExogenized = nnz(inxExogenized);
                numEndogenized = nnz(inxEndogenized);
                deficiency = 0;
                covariance = [ ];
                if numExogenized==numEndogenized
                    return
                end
                if numExogenized<numEndogenized
                   if plan.AllowUnderdetermined
                       return
                   end
                   deficiency = -1;
                elseif numExogenized>numEndogenized
                    if plan.AllowOverdetermined
                        return
                    end
                    deficiency = 1;
                end
            end%


            function hereReportDeficiencyOfPlan( )
                temp = cell.empty(1, 0);
                for ii = 1 : numel(deficiency)
                    for jj = find(deficiency{ii}~=0)
                        if deficiency{ii}(jj)==-1
                            description = 'Underdetermined';
                        else
                            description = 'Overdetermined';
                        end
                        temp{end+1} = sprintf( '[Page:%g][TimeFrame:%g]: %s', ...
                                               ii, jj, description );
                    end
                end
                thisError = { 'Model:DeficientSimulationPlan' 
                              'Simulation Plan is deficient in %s' };
                throw(exception.Base(thisError, 'error'), temp{:});
            end%
    end%




    function herePrepareBlazer( )
        firstColumnToRun = runningData.BaseRangeColumns(1);
        lastColumnToRun = runningData.BaseRangeColumns(end);
        switch opt.Method
            case {solver.Method.STACKED, solver.Method.STATIC}
                blazer = prepareBlazer(this, opt.Method, opt);
                blazer.ColumnsToRun = firstColumnToRun : lastColumnToRun;
                run(blazer, opt);

                opt.Blocks = false;
                blazerNoBlocks = prepareBlazer(this, opt.Method, opt);
                blazerNoBlocks.ColumnsToRun = firstColumnToRun : lastColumnToRun;
                run(blazerNoBlocks, opt);
                opt.Blocks = true;

                runningData.Blazers = [blazerNoBlocks, blazer];
            otherwise
                runningData.Blazers = [ ];
        end
    end%




    function systemProperty = hereSetupSystemProperty( )
        systemProperty = SystemProperty(this);
        systemProperty.Function = @simulateTimeFrames;
        systemProperty.MaxNumOfOutputs = 1;
        systemProperty.NamedReferences = cell(1, 1);
        systemProperty.NamedReferences{1} = this.Quantity.Name;
        systemProperty.Specifics = runningData;
        if isequal(opt.SystemProperty, false)
            systemProperty.OutputNames = cell(1, 0);
        else
            systemProperty.OutputNames = opt.SystemProperty;
        end
    end%




    function progressInfo = herePrepareProgressInfo( )
        oneLiner = true;
        if isa(opt.SolverOptions, 'solver.Options')
            solverDisplay = { opt.SolverOptions.Display };
            for ii = 1 : numel(solverDisplay)
                if ~isequal(solverDisplay{ii}, false) ...
                   && ~strcmpi(solverDisplay{ii}, 'None') ...
                   && ~strcmpi(solverDisplay{ii}, 'Off')
                   oneLiner = false;
                   break
                end
            end
        end
        progressInfo = ProgressInfo(runningData.NumOfPages, oneLiner);
        update(progressInfo);
    end%




    function hereCheckInitialConditions( )
        if isAsynchronous
            return
        end
        % Report missing initial conditions
        firstColumnOfSimulation = runningData.BaseRangeColumns(1);
        inxNaNPresample = any(isnan(runningData.YXEPG(:, 1:firstColumnOfSimulation-1, :)), 3);
        checkInitialConditions(this, inxNaNPresample, firstColumnOfSimulation);
    end%




    function numDummyPeriods = hereCalculateNumOfDummyPeriods( )
        numDummyPeriods = opt.Window - 1;
        if ~strcmpi(opt.Method, 'FirstOrder')
            [~, maxShift] = getActualMinMaxShifts(this);
            numDummyPeriods = numDummyPeriods + maxShift;
        end
        if numDummyPeriods>0
            plan = extendWithDummies(plan, numDummyPeriods);
        end
    end%




    function hereUpdateProgressInfo(run)
        progressInfo.Completed = run;
        progressInfo.Success = nnz(runningData.Success);
        update(progressInfo);
    end%




    function outputDb = hereCreateOutputData( )
        if strcmpi(opt.OutputData, 'Databank')
            if opt.Contributions
                comments = this.Quantity.Label4ShockContributions;
            else
                comments = this.Quantity.LabelOrName;
            end
            inxToInclude = ~getIndexByType(this.Quantity, TYPE(4));
            baseRange = runningData.BaseRange;
            startOfExtendedRange = runningData.ExtendedRange(1);
            lastColumnOfSimulation = runningData.BaseRangeColumns(end);
            timeSeriesConstructor = @default;
            outputDb = databank.backend.fromDoubleArrayNoFrills( runningData.YXEPG(:, 1:lastColumnOfSimulation, :), ...
                                                                   this.Quantity.Name, ...
                                                                   startOfExtendedRange, ...
                                                                   comments, ...
                                                                   inxToInclude, ...
                                                                   timeSeriesConstructor, ...
                                                                   opt.OutputType );
            outputDb = addToDatabank('Default', this, outputDb);
            if validate.databank(inputDb)
                outputDb = appendData(this, inputDb, outputDb, baseRange, opt);
            end
        else
            outputDb = runningData.YXEPG;
        end
    end%




    function outputInfo = herePrepareOutputInfo( )
        outputInfo = struct( );
        if ~runningData.PrepareOutputInfo
            return
        end
        outputInfo.TimeFrames = runningData.TimeFrames;
        outputInfo.TimeFrameDates = runningData.TimeFrameDates;
        outputInfo.BaseRange = DateWrapper(runningData.BaseRange);
        outputInfo.ExtendedRange = DateWrapper(runningData.ExtendedRange);
        outputInfo.Success =  runningData.Success;
        outputInfo.ExitFlags = runningData.ExitFlags;
        outputInfo.DiscrepancyTables = runningData.DiscrepancyTables;
    end%




    function herePostprocessContributions( )
        inxLog = this.Quantity.InxOfLog;
        if opt.Method~=solver.Method.FIRST_ORDER
            % Calculate contributions of nonlinearities
            runningData.YXEPG(inxLog, :, end) =  runningData.YXEPG(inxLog, :, end) ...
                                    ./ prod(runningData.YXEPG(inxLog, :, 1:end-1), 3);
            runningData.YXEPG(~inxLog, :, end) = runningData.YXEPG(~inxLog, :, end) ...
                                     - sum(runningData.YXEPG(~inxLog, :, 1:end-1), 3);
        end
    end%
end%


%
% Local Functions
%


function flag = validateMethod(x)
    listOfMethods = {'FirstOrder', 'Selective', 'Stacked', 'NoForward'};
    if validate.anyString(x, listOfMethods{:})
        flag = true;
    end    
    if iscell(x) && ~isempty(x) ...
       && validate.anyString(x{1}, listOfMethods{:}) ...
       && iscellstr(x(2:2:end))
        flag = true;
    end
    flag = false; 
end%




function flag = validateSolver(x)
    flag = isequal(x, @auto) || isa(x, 'solver.Options') || validateSolverName(x) ...
           || (iscell(x) && validateSolverName(x{1}) && iscellstr(x(2:2:end)));
end%




function flag = validateSolverName(x)
    if ~ischar(x) && ~isa(x, 'string') && ~isa(x, 'function_handle')
        flag = false;
        return
    end
    listSolverNames = { 
        'auto' 
        'IRIS-QaD'
        'IRIS-Newton'
        'IRIS-Qnsd'
        'QaD'
        'IRIS'
        'fminsearch'
        'lsqnonlin'
        'fsolve'      
    };
    flag = any(strcmpi(char(x), listSolverNames));
end%




function solverOption = hereResolveSolverOption(solverOption)
    if ischar(solverOption) || isstring(solverOption)
        solverName = solverOption;
        keep = cell.empty(1, 0);
    elseif iscell(solverOption)
        solverName = solverOption{1};
        keep = solverOption(2:end);
    else
        return
    end
    if strcmpi(solverName, 'fminsearch')
        solverOption = optimset(keep{:});
        solverOption.SolverName = 'fminsearch';
    end
end%




function [windowOption, baseRange] = parseWindowOptionAndBaseRange(windowOption, methodOption, baseRange)
    if isequal(baseRange, @auto)
        if isequal(windowOption, @auto) || isequal(windowOption, @max)
            baseRange = 1;
            windowOption = 1;
            return
        else
            baseRange = 1 : windowOption;
            return
        end
    end

    if isequal(windowOption, @auto)
        if methodOption==solver.Method.FIRST_ORDER
            windowOption = 1;
        else
            windowOption = @max;
        end
    end
    lenBaseRange = round(baseRange(end) - baseRange(1) + 1);
    if isequal(windowOption, @max)
        windowOption = lenBaseRange;
    elseif isnumeric(windowOption) && windowOption>lenBaseRange
        thisError = { 'Model:WindowCannotExceedRangeLength'
                      'Simulation windowOption cannot exceed number of simulation periods' };
        throw(exception.Base(thisError, 'error'));
    end
end%




function solverOption = parseSolverOption(solverOption, methodOption)
    switch methodOption
        case solver.Method.FIRST_ORDER
            solverOption = [ ];
        case solver.Method.SELECTIVE
            defaultSolver = 'IRIS-QaD';
            prepareGradient = false;
            displayMode = 'Verbose';
            solverOption = solver.Options.parseOptions( solverOption, ...
                                                        defaultSolver, ...
                                                        prepareGradient, ...
                                                        displayMode );
        case {solver.Method.STACKED, solver.Method.STATIC}
            defaultSolver = 'IRIS-Newton';
            prepareGradient = false;
            displayMode = 'Verbose';
            solverOption = solver.Options.parseOptions( solverOption, ...
                                                        defaultSolver, ...
                                                        prepareGradient, ...
                                                        displayMode );
    end
end%




function [timeFrames, mixinUnanticipated] = hereSplitIntoTimeFrames(unanticipatedE, baseRangeColumns, plan, maxShift, opt)
    inxUnanticipatedE = unanticipatedE~=0;
    inxUnanticipatedAny = inxUnanticipatedE | plan.InxOfUnanticipatedEndogenized;
    posUnanticipatedAny = find(any(inxUnanticipatedAny, 1));
    firstColumnOfSimulation = baseRangeColumns(1);
    lastColumnOfSimulation = baseRangeColumns(end);

    % TODO: For some simulations, unanticipated shocks can be mixed in with
    % anticipated shocks within a single time frame.
    mixinUnanticipated = hereTestMixinUnanticipated( );
    if mixinUnanticipated
       timeFrames = [firstColumnOfSimulation, lastColumnOfSimulation];
       return
    end

    if ~any(posUnanticipatedAny==firstColumnOfSimulation)
        posUnanticipatedAny = [firstColumnOfSimulation, posUnanticipatedAny];
    end
    columnOfLastAnticipatedExogenizedYX = plan.ColumnOfLastAnticipatedExogenized;
    numTimeFrames = numel(posUnanticipatedAny);
    timeFrames = nan(numTimeFrames, 2);
    for i = 1 : numTimeFrames
        startOfTimeFrame = posUnanticipatedAny(i);
        if i==numTimeFrames
            endOfTimeFrame = lastColumnOfSimulation;
        else
            endOfTimeFrame = max([posUnanticipatedAny(i+1)-1, columnOfLastAnticipatedExogenizedYX]);
        end
        lenTimeFrame = endOfTimeFrame - startOfTimeFrame + 1;
        minLenOfTimeFrame = opt.Window;
        if strcmpi(opt.Method, 'Selective')
            minLenOfTimeFrame = minLenOfTimeFrame + maxShift;
        end
        if lenTimeFrame<minLenOfTimeFrame
            endOfTimeFrame = endOfTimeFrame + (minLenOfTimeFrame - lenTimeFrame);
            lenTimeFrame = minLenOfTimeFrame;
        end
        timeFrames(i, :) = [startOfTimeFrame, endOfTimeFrame];
    end
    mixinUnanticipated = false;

    return


        function flag = hereTestMixinUnanticipated( )
            if opt.Method==solver.Method.FIRST_ORDER ...
               && plan.NumOfExogenizedPoints==0
                flag = true;
                return
            end
            if opt.Method==solver.Method.STATIC
                flag = true;
                return
            end
            flag = false;
        end%
end%
