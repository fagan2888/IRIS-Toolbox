function varargout = createModelData(this, dataBlock)
% createModelData  Create data matrices for ExplanatoryEquation model
%
% Backend [IrisToolbox] function
% No help provided

% -[IrisToolbox] for Macroeconomic Modeling
% -Copyright (c) 2007-2020 IRIS Solutions Team

% Invoke unit tests
%(
if nargin==2 && isequal(dataBlock, '--test')
    varargout{1} = unitTests( );
    return
end
%)

%--------------------------------------------------------------------------

%
% Create array of plain data for this single ExplanatoryEquation consisting
% of a block of rows with variables followed by one row of residuals
%
plainData = dataBlock.YXEPG(this.Runtime.PosPlainData, :, :);

numExtendedPeriods = size(plainData, 2);
numPages = size(plainData, 3);
baseRangeColumns = dataBlock.BaseRangeColumns;
baseRange = dataBlock.BaseRange;

%
% Model data for the dependent term
%
lhs = nan(1, numExtendedPeriods, numPages);
lhs(1, baseRangeColumns, :) = createModelData(this.Dependent, plainData, baseRangeColumns, baseRange);

%
% Model data for all explanatory terms
%
rhs = nan(numel(this.Explanatory), numExtendedPeriods, numPages);
rhs(:, baseRangeColumns, :) = createModelData(this.Explanatory, plainData, baseRangeColumns, baseRange);

%
% Model data for residuals; reset NaN residuals to zero
%
res = [ ];
if nargout>=4
    res = dataBlock.YXEPG(this.Runtime.PosResidual, :, :);
    hereFixResidualsInBaseRange( );
end


%<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<
varargout = {plainData, lhs, rhs, res};
%<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<

return

    function hereFixResidualsInBaseRange( )
        res__ = res(:, baseRangeColumns, :);
        inxNaN = isnan(res__);
        if nnz(inxNaN)==0
            return
        end
        res__(inxNaN) = 0;
        res(:, baseRangeColumns, :) = res__;
    end%
end%




%
% Unit Tests 
%
%(
function tests = unitTests( )
    tests = functiontests({ @setupOnce
                                @yxeSingleTest
                                @yxeSystem1Test 
                                @yxeSystem2Test });
    tests = reshape(tests, [ ], 1);
end%


function setupOnce(testCase)
    testCase.TestData.Model1 = ExplanatoryEquation.fromString("log(x) = ?*a + b*x{-1} + ?*log(c) + ?*y{+1} - ? + d");
    testCase.TestData.Model2 = ExplanatoryEquation.fromString("log(m) = ?*a + b*m{-1} + ?*log(c) + ?*n{+1} - ? + d");
    baseRange = qq(2001,1) : qq(2010,10);
    extendedRange = baseRange(1)-1 : baseRange(end)+1;
    db = struct( );
    db.x = Series(extendedRange, @rand);
    db.m = Series(extendedRange, @rand);
    db.a = Series(baseRange, @rand);
    db.b = Series(baseRange, @rand);
    db.c = Series(baseRange, @rand);
    db.d = Series(extendedRange, @rand);
    db.y = Series(extendedRange, @rand);
    db.n = Series(extendedRange, @rand);
    db.res_x = Series(extendedRange(5:10), @rand);
    db.res_m = Series(extendedRange(5:10), @rand);
    testCase.TestData.BaseRange = baseRange;
    testCase.TestData.ExtendedRange = extendedRange;
    testCase.TestData.Databank = db;
end%


function yxeSingleTest(testCase)
    m = testCase.TestData.Model1;
    db = testCase.TestData.Databank;
    baseRange = testCase.TestData.BaseRange;
    extendedRange = testCase.TestData.ExtendedRange;
    numExtendedPeriods = numel(extendedRange);
    lhsRequired = true; 
    dataBlock = getDataBlock(m, db, baseRange, lhsRequired, "");
    baseRangeColumns = dataBlock.BaseRangeColumns;
    m = runtime(m, dataBlock, "");
    [plain, lhs, rhs, res] = createModelData(m, dataBlock);
    exp_y = nan(1, numExtendedPeriods);
    exp_y(baseRangeColumns) = log(db.x(baseRange));
    assertEqual(testCase, lhs, exp_y);

    exp_rhs = nan(5, numExtendedPeriods);
    exp_rhs(1, baseRangeColumns) = db.a(baseRange);
    exp_rhs(2, baseRangeColumns) = log(db.c(baseRange));
    exp_rhs(3, baseRangeColumns) = db.y(baseRange+1);
    exp_rhs(4, baseRangeColumns) = -1;
    exp_rhs(5, baseRangeColumns) = db.b(baseRange).*db.x(baseRange-1) + db.d(baseRange);
    assertEqual(testCase, rhs, exp_rhs);
    exp_res = nan(1, numExtendedPeriods);
    temp = db.res_x(baseRange);
    temp(isnan(temp)) = 0;
    exp_res(1, baseRangeColumns) = temp;
    assertEqual(testCase, res, exp_res);

    exp_plain = nan(7, numExtendedPeriods);
    exp_plain(1, :) = db.x(extendedRange);
    exp_plain(2, :) = db.a(extendedRange);
    exp_plain(3, :) = db.b(extendedRange);
    exp_plain(4, :) = db.c(extendedRange);
    exp_plain(5, :) = db.y(extendedRange);
    exp_plain(6, :) = db.d(extendedRange);
    exp_plain(7, :) = db.res_x(extendedRange);
    assertEqual(testCase, plain, exp_plain);
end%


function yxeSystem1Test(testCase)
    m1 = testCase.TestData.Model1;
    m2 = testCase.TestData.Model2;
    m = [m1, m2];
    db = testCase.TestData.Databank;
    baseRange = testCase.TestData.BaseRange;
    extendedRange = testCase.TestData.ExtendedRange;
    numExtendedPeriods = numel(extendedRange);
    lhsRequired = true; 
    dataBlock = getDataBlock(m, db, baseRange, lhsRequired, "");
    baseRangeColumns = dataBlock.BaseRangeColumns;
    m(1) = runtime(m(1), dataBlock, "");
    [plain, lhs, rhs, res] = createModelData(m(1), dataBlock);
    exp_y = nan(1, numExtendedPeriods);
    exp_y(baseRangeColumns) = log(db.x(baseRange));
    assertEqual(testCase, lhs, exp_y);

    exp_rhs = nan(5, numExtendedPeriods);
    exp_rhs(1, baseRangeColumns) = db.a(baseRange);
    exp_rhs(2, baseRangeColumns) = log(db.c(baseRange));
    exp_rhs(3, baseRangeColumns) = db.y(baseRange+1);
    exp_rhs(4, baseRangeColumns) = -1;
    exp_rhs(5, baseRangeColumns) = db.b(baseRange).*db.x(baseRange-1) + db.d(baseRange);
    assertEqual(testCase, rhs, exp_rhs);

    exp_res = nan(1, numExtendedPeriods);
    temp = db.res_x(baseRange);
    temp(isnan(temp)) = 0;
    exp_res(1, baseRangeColumns) = temp;
    assertEqual(testCase, res, exp_res);

    exp_plain = nan(7, numExtendedPeriods);
    exp_plain(1, :) = db.x(extendedRange);
    exp_plain(2, :) = db.a(extendedRange);
    exp_plain(3, :) = db.b(extendedRange);
    exp_plain(4, :) = db.c(extendedRange);
    exp_plain(5, :) = db.y(extendedRange);
    exp_plain(6, :) = db.d(extendedRange);
    exp_plain(7, :) = db.res_x(extendedRange);
    assertEqual(testCase, plain, exp_plain);
end%


function yxeSystem2Test(testCase)
    m1 = testCase.TestData.Model1;
    m2 = testCase.TestData.Model2;
    m = [m1, m2];
    db = testCase.TestData.Databank;
    baseRange = testCase.TestData.BaseRange;
    extendedRange = testCase.TestData.ExtendedRange;
    numExtendedPeriods = numel(extendedRange);
    lhsRequired = true; 
    dataBlock = getDataBlock(m, db, baseRange, lhsRequired, "");
    baseRangeColumns = dataBlock.BaseRangeColumns;
    m(2) = runtime(m(2), dataBlock, "");
    [plain, lhs, rhs, res] = createModelData(m(2), dataBlock);
    exp_y = nan(1, numExtendedPeriods);
    exp_y(baseRangeColumns) = log(db.m(baseRange));
    assertEqual(testCase, lhs, exp_y);

    exp_rhs = nan(5, numExtendedPeriods);
    exp_rhs(1, baseRangeColumns) = db.a(baseRange);
    exp_rhs(2, baseRangeColumns) = log(db.c(baseRange));
    exp_rhs(3, baseRangeColumns) = db.n(baseRange+1);
    exp_rhs(4, baseRangeColumns) = -1;
    exp_rhs(5, baseRangeColumns) = db.b(baseRange).*db.m(baseRange-1) + db.d(baseRange);
    assertEqual(testCase, rhs, exp_rhs);

    exp_res = nan(1, numExtendedPeriods);
    temp = db.res_m(baseRange);
    temp(isnan(temp)) = 0;
    exp_res(1, baseRangeColumns) = temp;
    assertEqual(testCase, res, exp_res);

    exp_plain = nan(7, numExtendedPeriods);
    exp_plain(1, :) = db.m(extendedRange);
    exp_plain(2, :) = db.a(extendedRange);
    exp_plain(3, :) = db.b(extendedRange);
    exp_plain(4, :) = db.c(extendedRange);
    exp_plain(5, :) = db.n(extendedRange);
    exp_plain(6, :) = db.d(extendedRange);
    exp_plain(7, :) = db.res_m(extendedRange);
    assertEqual(testCase, plain, exp_plain);
end%
%)

