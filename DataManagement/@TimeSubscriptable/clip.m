function [this, newStart, newEnd] = clip(this, newStart, newEnd)
% clip  Clip time series range
%{
% ## Syntax ##
%
%     outputSeries = clip(inputSeries, newStart, newEnd)
%
%
% ## Input Arguments ##
%
%
% __`inputSeries`__ [ TimeSubscriptable ]
% >
% Input time series whose date range will be clipped.
%
%
% __`newStart`__ [ DateWrapper | `-Inf` ]
% >
% New start date; `-Inf` means keep the current start date.
%
%
% __`newEnd`__ [ DateWrapper | `Inf` ]
% >
% New end date; `Inf` means keep the current enddate.
%
%
% ## Output Arguments ##
%
%
% __`outputSeries`__ [ TimeSubscriptable ]
% Output time series  with its date range clipped to the new range from
% `newStart` to `newEnd`.
%
%
% ## Description ##
%
%
%
% ## Example ##
%
%}

% -[IrisToolbox] for Macroeconomic Modeling
% -Copyright (c) 2007-2020 IRIS Solutions Team

persistent parser
if isempty(parser)
    parser = extend.InputParser('TimeSubscriptable.clip');
    parser.addRequired('inputSeries', @(x) isa(x, 'TimeSubscriptable'));
    parser.addRequired('newStart', @(x) DateWrapper.validateDateInput(x) && isscalar(x));
    parser.addRequired('newEnd', @(x) DateWrapper.validateDateInput(x) && isscalar(x) && ~isequal(x, -Inf));
end
parser.parse(this, newStart, newEnd);

%--------------------------------------------------------------------------

if isnan(this.Start) && isempty(this.Data)
    return
end

if isequaln(newStart, NaN) || isequaln(newEnd, NaN)
    this = emptyData(this);
    return
end

isStartInf = isequal(newStart, -Inf) || isequal(newStart, Inf);
isEndInf = isequal(newEnd, Inf);
if isStartInf && isEndInf
    if nargout>1
        newStart = this.Start;
        newEnd = this.End;
    end
    return
end

serialXStart = round(this.Start);
serialXEnd = round(serialXStart + size(this.Data, 1) - 1);
freqOfX = DateWrapper.getFrequencyAsNumeric(this.Start);

serialNewStart = getSerialNewStart( );
serialNewEnd = getSerialNewEnd( );

% Return immediately the input time series if the new start is before the
% input start and the new end is after the input end
if serialNewStart<=serialXStart && serialNewEnd>=serialXEnd
    if nargout>1
        newStart = this.Start;
        newEnd = this.End;
    end
    return
end

% Return immediately an empty time series if 
% * the new start is after the new end
% * both the new start and end are before the start of the series
% * both the new start and end are after the end of the series
if serialNewStart>serialNewEnd ...
   || (serialNewStart<serialXStart && serialNewEnd<serialXStart) ...
   || (serialNewStart>serialXEnd && serialNewEnd>serialXEnd)
    this = this.empty(this);
    if nargout>1
        newStart = this.Start;
        newENd = this.End;
    end
    return
end

sizeOfData = size(this.Data);
ndimsOfData = ndims(this.Data);
if serialNewStart>serialXStart
    numRowsToRemove = round(serialNewStart - serialXStart);
    this.Data(1:numRowsToRemove, :) = [ ];
    this.Start = DateWrapper.fromSerial(freqOfX, serialNewStart);
end

if serialNewEnd<serialXEnd
    numRowsToRemove = round(serialXEnd - serialNewEnd);
    this.Data(end-numRowsToRemove+1:end, :) = [ ];
end

if ndimsOfData>2
    sizeOfData(1) = size(this.Data, 1);
    this.Data = reshape(this.Data, sizeOfData);
end

this = trim(this);

return


    function serialNewStart = getSerialNewStart( )
        if isStartInf
            serialNewStart = serialXStart;
        else
            freqOfNewStart = DateWrapper.getFrequencyAsNumeric(newStart);
            if freqOfNewStart~=freqOfX
                throw( exception.Base('Series:FrequencyMismatch', 'error'), ...
                       Frequency.toChar(freqOfX), Frequency.toChar(freqOfNewStart) );
            end
            serialNewStart = round(newStart);
        end
    end%


    function serialNewEnd = getSerialNewEnd( )
        if isEndInf
            serialNewEnd = serialXEnd;
        else
            freqOfNewEnd = DateWrapper.getFrequencyAsNumeric(newEnd);
            if freqOfNewEnd~=freqOfX
                throw( exception.Base('Series:FrequencyMismatch', 'error'), ...
                       Frequency.toChar(freqOfX), Frequency.toChar(freqOfNewEnd) );
            end
            serialNewEnd = round(newEnd);
        end
    end%
end%
