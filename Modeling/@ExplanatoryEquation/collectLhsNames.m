function lhsNames = collectLhsNames(this)
% collectLhsNames  Collect names of LHS variables 
%{
% ## Syntax ##
%
%
%     lhsNames = collectRhsNames(this)
%
%
% ## Input Arguments ##
%
%
% __`this`__ [ ExplanatoryEquation ]
% >
% ExplanatoryEquation object or array whose LHS variables will be returned.
%
%
% ## Output Arguments ##
%
%
% __`lhsNames`__ [ string ]
% >
% Names of the LHS variables in `this` ExplanatoryEquation object or array.
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
% -Copyright (c) 2007-2020 [IrisToolbox] Solutions Team

%--------------------------------------------------------------------------

lhsNames = [this.LhsName];

end%

