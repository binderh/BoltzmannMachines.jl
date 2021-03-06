"
Contains all plotting functions for displaying information collected
in module `BoltzmannMachines`. Most important function is `plotevaluation`.
"
module BMPlots

import ..BoltzmannMachines
const BMs = BoltzmannMachines

export plotevaluation


# global flag to load Gadfly and related packages only when necessary and
# only once
gadflyinitialized = false

# Called when loading the package, initializes Gadfly only if it is installed
function __init__()
   if Pkg.installed("Gadfly") != nothing
      initgadfly()
   end
end


function initgadfly()
   @eval begin
      using DataFrames, Gadfly, Compose
      gadflyinitialized = true
   end
end


function requiresgadfly()
   if !gadflyinitialized
      if Pkg.installed("Gadfly") == nothing
         error("Plotting requires Gadfly. Please install package \"Gadfly\".")
      else
         initgadfly()
      end
   end
end


function checkdata(plotdata)
   if size(plotdata, 1) == 0
      error("No data for this evaluation in monitor")
   end
end

function getvalue(monitor::BMs.Monitor, evaluation::AbstractString, epoch::Int)
   itemidx = findfirst((item -> item.evaluation == evaluation && item.epoch == epoch), monitor)
   monitor[itemidx].value
end

function extractevaluationdata(monitor::BMs.Monitor, evaluation::AbstractString)
   evaluationidxs = find(item -> item.evaluation == evaluation, monitor)
   epochs = map(i -> monitor[i].epoch, evaluationidxs)
   values = map(i -> monitor[i].value, evaluationidxs)
   datasetnames = map(i -> monitor[i].datasetname, evaluationidxs)
   plotdata = DataFrame(epoch = epochs, value = values, datasetname = datasetnames)
end

function extractaisdata(monitor::BMs.Monitor, evaluation::AbstractString, sdrange::Float64)

   plotdata = extractevaluationdata(monitor, evaluation)

   # Now integrate the information about the precision of AIS in the dataframe.
   # It is common for all datasets.
   epochs = unique(plotdata[:epoch])

   if sdrange != 0.0

      plotdata[:ymin] = copy(plotdata[:value])
      plotdata[:ymax] = copy(plotdata[:value])

      # Use standard deviation of log partition function estimator to
      # plot ribbon around log probs.
      for epoch in epochs
         sd = getvalue(monitor, BMs.monitoraisstandarddeviation, epoch)
         r = getvalue(monitor, BMs.monitoraisr, epoch)

         # log(Z) is subtracted from logproblowerbound, so overstimating log(Z)
         # means underestimating the log probability
         bottom, top = BMs.aisprecision(r, sd, sdrange)
         plotdata[:ymin][plotdata[:epoch] .== epoch] -= top
         plotdata[:ymax][plotdata[:epoch] .== epoch] -= bottom
      end
   end

   plotdata
end

"
Plots the information about the estimated lower bound of the log probability
that has been gathered while training a BMs.
"
function plotlogproblowerbound(monitor::BMs.Monitor; sdrange::Float64 = 0.0)
   requiresgadfly()
   title = "Average lower bound of log probability"
   plotdata = extractaisdata(monitor, BMs.monitorlogproblowerbound, sdrange)
   checkdata(plotdata)
   if sdrange != 0
      plot(plotdata, x = "epoch", y = "value", ymin = "ymin", ymax = "ymax", color = "datasetname",
         Geom.line, Geom.ribbon,
         Guide.title(title))
   else
      plot(plotdata, x = "epoch", y = "value", color = "datasetname",
            Geom.line, Guide.title(title))
   end
end

function plotexactloglikelihood(monitor::BMs.Monitor)
   plotevaluation(monitor, BMs.monitorexactloglikelihood)
end

plottitledict = Dict(
      BMs.monitorreconstructionerror => "Mean reconstruction error",
      BMs.monitorloglikelihood => "Log-likelihood estimated by AIS",
      BMs.monitorexactloglikelihood => "Exact log-likelihood",
      BMs.monitorweightsnorm => "L²-norm of weights",
      BMs.monitorsd => "Standard deviation parameters of visible units",
      BMs.monitorcordiff => "L²-difference between correlation matrices \nof generated and original data",
      BMs.monitorfreeenergy => "Free energy")


"""
    plotevaluation(monitor, evaluationkey; ...)
Plots a curve that shows the values of the evaluation contained in the `monitor`
and specified by the `evaluationkey` over the course of the training epochs.

Optional keyword argument `sdrange`:
For evaluations with keys `BoltzmannMachines.monitorloglikelihood` and
`BoltzmannMachines.monitorlogproblowerbound`,
there is additional information about the standard
deviation of the estimator. With the parameter `sdrange`, it is possible
to display this information as a ribbon around the curve. The ribbon indicates
the area around the curve that contains the values that deviate at maximum
`sdrange` times the standard deviation from the estimator.
Default value for `sdrange` is 2.0.
"""
function plotevaluation(monitor::BMs.Monitor, evaluationkey::AbstractString;
      sdrange::Float64 = 2.0)

   if evaluationkey == BMs.monitorloglikelihood
      return plotloglikelihood(monitor, sdrange = sdrange)
   elseif evaluationkey == BMs.monitorlogproblowerbound
      return plotlogproblowerbound(monitor, sdrange = sdrange)
   end

   # Otherwise, it is a simple line plot.
   requiresgadfly()
   title = get(plottitledict, evaluationkey, evaluationkey)
   plotdata = extractevaluationdata(monitor, evaluationkey)
   checkdata(plotdata)
   plot(plotdata, x ="epoch", y = "value", color = "datasetname",
         Geom.line, Guide.title(title))
end

"
Plots the information about the log likelihood that has been gathered while
training an RBMs.
"
function plotloglikelihood(monitor::BMs.Monitor; sdrange::Float64 = 2.0)
   requiresgadfly()
   plotdata = extractaisdata(monitor, BMs.monitorloglikelihood, sdrange)
   checkdata(plotdata)
   title = "Average log-likelihood"
   if sdrange != 0
      plot(plotdata, x = "epoch", y = "value", ymin = "ymin", ymax = "ymax", color = "datasetname",
         Geom.line, Geom.ribbon,
         Guide.title(title))
   else
      plot(plotdata, x = "epoch", y = "value", color = "datasetname",
            Geom.line, Guide.title(title))
   end
end

function plotreconstructionerror(monitor::BMs.Monitor)
   plotevaluation(monitor, BMs.monitorreconstructionerror)
end

function emptyfunc
end

function bivariategaussiandensity(x1::Vector{Float64}, x2::Vector{Float64})
   c = cov(x1, x2)
   s = [var(x1) c; c var(x2)]
   sinv = inv(s)
   factor = 1 / (2pi * sqrt(det(s)))
   mu = [mean(x1); mean(x2)]
   (x,y) -> factor * exp(-0.5 * dot([x;y] - mu, sinv * ([x;y] - mu)))
end

"
Pairs plot for each variable of the data set `x` versus each other variable.
"
function plotpairs(x::Matrix{Float64};
      filename::AbstractString = "pairs",
      labels = Vector{AbstractString}(),
      cellsize = 0,
      subgroups = Vector{AbstractString}(),
      densityestimation::Function = emptyfunc,
      datafordensityestimation::Matrix{Float64} = x)

   requiresgadfly()
   if cellsize == 0
      cellsize = 60mm
   end

   nvariables = size(x,2)
   nlabels = length(labels)

   # label all unlabeled variables with "x1", "x2", ...
   if nlabels < nvariables
      labels = [labels; [string("x",i) for i = 1:(nvariables-nlabels)]];
   end

   plotdata = convert(DataFrame,
         Dict(zip(labels, [ x[:,i] for i = 1:nvariables ])));

   if isempty(subgroups)
      subgroups = repmat([""], size(plotdata, 1))
   end
   plotdata[:subgroup] = subgroups

   if densityestimation != emptyfunc
      mins = [minimum(x[:,i])::Float64 for i = 1:nvariables]
      maxs = [maximum(x[:,i])::Float64 for i = 1:nvariables]
   end

   grid = Array(Compose.Context, (nvariables, nvariables))
   for i = 1:nvariables
      for j = 1:nvariables
         if i == j
            grid[i,j] = render(plot(plotdata, x = labels[i],
                  color = "subgroup",
                  Theme(key_position = :none), # do not show legend
                  Geom.histogram))
         else
            if densityestimation != emptyfunc
               # bug in Gadfly: contour plot only if other layer has no subgroups
               estimateddensityfunction = densityestimation(
                     datafordensityestimation[:,i],
                     datafordensityestimation[:,j])
               grid[i,j] = render(plot(
                     layer(z = estimateddensityfunction,
                           x = linspace(mins[i], maxs[i], 100),
                           y = linspace(mins[j], maxs[j], 100), Geom.contour),
                     layer(plotdata, x = labels[i], y = labels[j],
                           Theme(key_position = :none),
                           Geom.point),
                     Theme(key_position = :none), # no color bars
                     Guide.xlabel(labels[i]), Guide.ylabel(labels[j])))
            else
               grid[i,j] = render(plot(plotdata, x = labels[i], y = labels[j],
                     color = "subgroup",
                     Theme(key_position = :none),
                     Geom.point))
            end
         end
      end
   end
   draw(PNG(string(filename, ".png"), nvariables*cellsize, nvariables*cellsize),
         gridstack(grid))
end


function scatterhidden(rbm::BMs.AbstractRBM, x::Matrix{Float64};
      hiddennodes::Tuple{Int,Int} = (1,2),
      labels = Vector{AbstractString}())

   hh = BMs.hiddenpotential(rbm, x)
   hh = hh[:,collect(hiddennodes)]

   if !isempty(labels)
      nsamples = size(x,1)
      plotdata = DataFrame(x = hh[:,1], y = hh[:,2])
      if length(labels) == nsamples
         plotdata[:label] = labels
      else
         error("Not enough labels ($(length(labels))) for samples ($(nsamples))")
      end
      plot(plotdata, x = "x", y = "y", color = "label", Geom.point)
   else
      plot(x = hh[:,1], y = hh[:,2], Geom.point)
   end

end

end # module BMPlots
