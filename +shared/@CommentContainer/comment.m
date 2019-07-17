function varargout = comment(this, varargin)
% comment  Get or set user comments in IRIS object
%
% ## Syntax for Getting User Comments ##
%
%     currentComment = comment(obj)
%
%
% ## Syntax for Assigning User Comments ##
%
%     obj = comment(obj, newComment)
%
%
% ## Input Arguments ##
%
% __`obj`__ [ model | tseries | VAR | SVAR | FAVAR | sstate ] –
% IRIS object subclassed from shared.CommentContainer.
%
% __`newComment`__ [ char | string ] –
% New user comment that will be attached to the object.
%
%
% ## Output Arguments ##
%
% __`currentComment`__ [ char ] –
% User comment that is currently attached to the object.
%
%
% ## Description ##
%
%
% ## Example ##
%

% -IRIS Macroeconomic Modeling Toolbox
% -Copyright (c) 2007-2019 IRIS Solutions Team

if ~isempty(varargin)
    newComment = varargin{1};
    parser = inputParser( );
    parser.addRequired('NewComment', @ischar);
    parser.parse(newComment);
end

%--------------------------------------------------------------------------

if isempty(varargin)
    varargout{1} = this.Comment;
else
    this.Comment = newComment;
    varargout{1} = this;
end

end%

