module BoltzmannMachines

const BMs = BoltzmannMachines

export
   AbstractBM,
      aisimportanceweights, aisprecision, aisstandarddeviation,
      empiricalloglikelihood, energy, exactloglikelihood,
      exactlogpartitionfunction, loglikelihood,
      logpartitionfunction, logpartitionfunctionzeroweights,
      logproblowerbound, reconstructionerror,
      sampleparticles,
      AbstractRBM,
         BernoulliRBM,
         BernoulliGaussianRBM,
         Binomial2BernoulliRBM,
         GaussianBernoulliRBM,
         fitrbm, freeenergy, initrbm, joinrbms,
         trainrbm!, samplehidden, samplevisible,
         hiddenpotential, hiddeninput, visiblepotential, visibleinput,
      AbstractDBM,
         BasicDBM,
         MultivisionDBM,
         addlayer!, fitdbm, gibbssample!, meanfield, stackrbms, traindbm!,
   Particle, Particles,
   Monitor, MonitoringItem, DataDict,
      monitorexactloglikelihood, monitorexactloglikelihood!,
      monitorfreeenergy, monitorfreeenergy!,
      monitorlogproblowerbound, monitorlogproblowerbound!,
      monitorloglikelihood, monitorloglikelihood!,
      monitorreconstructionerror, monitorreconstructionerror!,
      monitorweightsnorm, monitorweightsnorm!,
      propagateforward,
   barsandstripes, splitdata,
   BMPlots


include("rbmtraining.jl")
include("dbmtraining.jl")

typealias AbstractBM Union{AbstractDBM, AbstractRBM}


"""
    barsandstripes(nsamples, nvariables)
Generates a test data set. To see the structure in the data set, run e. g.
`reshape(barsandstripes(1, 16), 4,4)` a few times.

Example from:
MacKay, D. (2003). Information Theory, Inference, and Learning Algorithms
"""
function barsandstripes(nsamples::Int, nvariables::Int)
   squareside = sqrt(nvariables)
   if squareside != floor(squareside)
      error("Number of variables must be a square number")
   end
   squareside = round(Int, squareside)
   x = zeros(nsamples, nvariables)
   for i in 1:nsamples
      sample = hcat([(rand() < 0.5 ? ones(squareside) : zeros(squareside))
            for j in 1:squareside]...)
      if rand() < 0.5
         sample = transpose(sample)
      end
      x[i,:] .= sample[:]
      fill!(sample, 0.0)
   end
   x
end


function sigm(x::Array{Float64,1})
   1./(1 + exp(-x))
end

function sigm(x::Array{Float64,2})
   1./(1 + exp(-x))
end

function bernoulli(x::Float64)
   float(rand() < x)
end

function bernoulli!(x::Array{Float64,1})
   map!(bernoulli, x)
end

function bernoulli(x::Array{Float64,1})
   float(rand(length(x)) .< x)
end

function bernoulli(x::Array{Float64,2})
   float(rand(size(x)) .< x)
end

"
    samplerbm(rbm, n)
    samplerbm(rbm, n, burnin)
Generates `n` samples from a given `rbm` by running a single Gibbs chain with
`burnin`.
"
function samplerbm(rbm::BernoulliRBM, n::Int, burnin::Int = 10)

   nvisible = length(rbm.visbias)
   nhidden = length(rbm.hidbias)

   x = zeros(n, nvisible)

   h = round(rand(nhidden))
   for i=1:(n+burnin)
      v = bernoulli!(visiblepotential(rbm, h))
      h = bernoulli!(hiddenpotential(rbm, v))

      if i > burnin
         x[i-burnin,:] = v
      end
   end

   x
end


"""
    splitdata(x, ratio)
Splits the data set `x` randomly in two data sets `x1` and `x2`, such that
the ratio `n2`/`n1` of the numbers of lines/samples in `x1` and `x2` is
approximately equal to the given `ratio`.
"""
function splitdata(x::Matrix{Float64}, ratio::Float64)
   nsamples = size(x,1)
   testidxs = randperm(nsamples)[1:(round(Int, nsamples*ratio))]
   xtest = x[testidxs,:]
   xtraining = x[setdiff(1:nsamples, testidxs),:]
   xtraining, xtest
end


function fitpartdbmcore(x::Array{Float64,2},
      nhiddens::Array{Int,1},
      visibleindex,
      epochs::Int = 10,
      nparticles::Int = 100;
      jointepochs::Int = epochs,
      learningrate::Float64 = 0.005,
      jointlearningrate::Float64 = learningrate,
      jointinitscale::Float64 = 1.0,
      topn::Int=0)

   nparts = length(visibleindex)
   p = size(x)[2]

   nhiddensmat = zeros(Int,nparts,length(nhiddens))
   for i=1:(nparts-1)
      nhiddensmat[i,:] = floor(nhiddens ./ (p/length(visibleindex[i])))
   end
   nhiddensmat[nparts,:] = nhiddens .- vec(sum(nhiddensmat,1))

   partparams = Array{Array{BMs.BernoulliRBM,1},1}(nparts)

   for i=1:nparts
      partparams[i] = fitdbm(x[:,visibleindex[i]];
            nhiddens = vec(nhiddensmat[i,:]),
            epochs = epochs, nparticles = nparticles,
            learningrate = learningrate)
   end

   params = Array{BMs.BernoulliRBM,1}(length(nhiddens))

   for i=1:length(nhiddens)
      curin = (i == 1 ? p : nhiddens[i-1])
      curout = nhiddens[i]
      if jointinitscale == 0.0
         weights = zeros(curin,curout)
      else
         weights = randn(curin,curout) / curin * jointinitscale
      end
      a = zeros(curin)
      b = zeros(curout)

      startposin = 1
      startposout = 1
      for j=1:nparts
         if i == 1
            inindex = visibleindex[j]
         else
            inindex = collect(startposin:(startposin+nhiddensmat[j,i-1]-1))
            startposin += nhiddensmat[j,i-1]
         end
         outindex = collect(startposout:(startposout+nhiddensmat[j,i]-1))
         startposout += nhiddensmat[j,i]

         weights[inindex,outindex] = partparams[j][i].weights
         a[inindex] = partparams[j][i].visbias
         b[outindex] = partparams[j][i].hidbias

         params[i] = BernoulliRBM(weights,a,b)
      end
   end

   if topn > 0
      bottomparams = params
      params = Array{BMs.BernoulliRBM,1}(length(nhiddens)+1)
      params[1:length(bottomparams)] = bottomparams
      topweights = randn(nhiddens[end],topn) / nhiddens[end] * jointinitscale
      topa = zeros(nhiddens[end])
      topb = zeros(topn)
      params[end] = BernoulliRBM(topweights,topa,topb)
   end

   if jointepochs == 0
      return params
   end

   traindbm!(params, x, epochs = jointepochs, nparticles = nparticles,learningrate=jointlearningrate)
end

function fitpartdbm(x::Array{Float64,2},
      nhiddens::Array{Int,1},
      nparts::Int = 2,
      epochs::Int = 10,
      nparticles::Int = 100;
      jointepochs::Int = epochs,
      learningrate::Float64 = 0.005,
      jointlearningrate::Float64 = learningrate,
      topn::Int=0)

   if (nparts < 2)
      return fitdbm(x, nhiddens = nhiddens, epochs = epochs,
            nparticles = nparticles)
   end

   partitions = Int(ceil(log(2,nparts)))
   nparts = 2^partitions
   p = size(x)[2]

   visibleindex = BMs.vispartcore(BMs.vistabs(x),collect(1:size(x)[2]),partitions)

   fitpartdbmcore(x,nhiddens,visibleindex,epochs,nparticles,jointepochs=jointepochs,learningrate=learningrate,jointlearningrate=jointlearningrate)
end


function sampledbm(dbm::BasicDBM, n::Int, burnin::Int=10, returnall=false)

   particles = initparticles(dbm, n)

   gibbssample!(particles, dbm, burnin)

   if returnall
      return particles
   else
      return particles[1]
   end
end


"""
    joindbms(dbms)
    joindbms(dbms, visibleindexes)
Joins the DBMs given by the vector `dbms` by joining each layer of RBMs.

If the vector `visibleindexes` is specified, it is supposed to contain in the 
i'th entry an indexing vector that determines the positions in the combined 
DBM for the visible nodes of the i'th of the `dbms`.
By default the indexes of the visible nodes are assumed to be consecutive.
"""
function joindbms(dbms::Vector{BasicDBM}, visibleindexes = [])
   jointdbm = BasicDBM(length(dbms[1]))
   jointdbm[1] = joinrbms([dbms[i][1] for i in eachindex(dbms)], 
         visibleindexes)
   for j = 2:length(dbms[1])
      jointdbm[j] = joinrbms([dbms[i][j] for i in eachindex(dbms)])
   end
   jointdbm
end


"""
    joinrbms(rbms)
    joinrbms(rbms, visibleindexes)
Joins the given vector of `rbms` of the same type to form one RBM of this type
and returns the joined RBM.
"""
function joinrbms{T<:AbstractRBM}(rbm1::T, rbm2::T)
   joinrbms(T[rbm1, rbm2])
end

function joinrbms(rbms::Vector{BernoulliRBM}, visibleindexes = [])
   jointvisiblebias = joinvecs([rbm.visbias for rbm in rbms], visibleindexes)
   jointhiddenbias = vcat(map(rbm -> rbm.hidbias, rbms)...)
   BernoulliRBM(joinweights(rbms, visibleindexes), 
         jointvisiblebias, jointhiddenbias)
end

function joinrbms(rbms::Vector{GaussianBernoulliRBM}, visibleindexes = [])
   jointvisiblebias = joinvecs([rbm.visbias for rbm in rbms], visibleindexes)
   jointhiddenbias = vcat(map(rbm -> rbm.hidbias, rbms)...)
   jointsd = joinvecs([rbm.sd for rbm in rbms], visibleindexes)
   GaussianBernoulliRBM(joinweights(rbms, visibleindexes), 
         jointvisiblebias, jointhiddenbias, jointsd)
end


"""
    joinvecs(vecs, indexes)
Combines the Float-vectors in `vecs` into one vector. The `indexes`` vector must
contain in the i'th entry the indexes that the elements of the i'th vector in 
`vecs` are supposed to have in the resulting combined vector.
"""
function joinvecs(vecs::Vector{Vector{Float64}}, indexes = [])
   if isempty(indexes)
      jointvec = vcat(vecs...)
   else
      jointlength = mapreduce(v -> length(v), +, 0, vecs)
      jointvec = Vector{Float64}(jointlength)
      for i in eachindex(vecs)
         jointvec[indexes[i]] = vecs[i]
      end
   end
   jointvec
end

"""
    joinweights(rbms)
    joinweights(rbms, visibleindexes)
Combines the weight matrices of the RBMs in the vector `rbms` into one weight 
matrix and returns it. 

If the vector `visibleindexes` is specified, it is supposed to contain in the 
i'th entry an indexing vector that determines the positions in the combined 
weight matrix for the visible nodes of the i'th of the `rbms`.
By default the indexes of the visible nodes are assumed to be consecutive.
"""
function joinweights{T<:AbstractRBM}(rbms::Vector{T}, visibleindexes = [])
   jointnhidden = mapreduce(rbm -> length(rbm.hidbias), +, 0, rbms)
   jointnvisible = mapreduce(rbm -> length(rbm.visbias), +, 0, rbms)
   jointweights = zeros(jointnvisible, jointnhidden)
   offset = 0

   # if visibleindexes are not provided, construct them
   if isempty(visibleindexes)
      visibleindexes = Array{UnitRange}(length(rbms))
      for i in eachindex(rbms)
         nvisible = length(rbms[i].visbias)
         visibleindexes[i] = offset + (1:nvisible)
         offset += nvisible
      end
   elseif length(visibleindexes) != length(rbms)
      error("There must be as many indexing vectors as RBMs.")
   end

   offset = 0
   for i = eachindex(rbms)
      nhidden = length(rbms[i].hidbias)
      jointweights[visibleindexes[i], offset + (1:nhidden)] = rbms[i].weights
      offset += nhidden
   end

   jointweights
end

"
Returns a matrix, containing in the entry [i,j]
the associations between the variables contained in the columns i and j
in the matrix `x` by calculating chi-squared-statistics.
"
function vistabs(x::Array{Float64,2})
   nsamples, nvariables = size(x)

   # freq[i] is number of times when unit i is on
   freq = sum(x,1)

   chisq = zeros(nvariables, nvariables)

   for i=1:(nvariables-1)
      for j=(i+1):nvariables

         # Contingency table:
         #
         # i\j | 1 0
         #  --------
         #   1 | a b
         #   0 | c d

         a = sum(x[:,i] .* x[:,j])
         b = freq[i] - a
         c = freq[j] - a
         d = nsamples - (a+b+c)

         chisq[i,j] = chisq[j,i] = (a*d - b*c)^2*nsamples/
               (freq[i]*freq[j]*(nsamples-freq[i])*(nsamples-freq[j]))
      end
   end

   chisq
end

function vispartcore(chisq,refindex,npart)
   p = size(chisq)[2]
   halfp = div(p,2)

   ifirst = ind2sub(chisq,indmax(chisq)) # coordinates of maximum element
   ifirstvec = chisq[ifirst[1],:] # all associations with maximum element
   ifirstvec[ifirst[1]] = maximum(chisq) + 1.0 # Association of maximum elements with itself is made highest

   diffind = sortperm(vec(ifirstvec);rev=true)

   firstindex = diffind[1:halfp]
   secondindex = diffind[(halfp+1):p]

   firstoriindex = refindex[firstindex]
   secondoriindex = refindex[secondindex]

   if npart == 1
      return Array[firstoriindex, secondoriindex]
   else
      return append!(vispartcore(chisq[firstindex,firstindex],firstoriindex,npart-1),vispartcore(chisq[secondindex,secondindex],secondoriindex,npart-1))
   end
end

function parttoindex(partvecs,index)
   for i=1:length(partvecs)
      if index in partvecs[i]
         return i
      end
   end
   0
end

function vispartition(x,npart=1)
   chisq = BMs.vistabs(x)
   partvecs = BMs.vispartcore(chisq,collect(1:size(x)[2]),npart)
   map(_ -> parttoindex(partvecs,_),1:size(x)[2])
end

"
Returns a matrix containing in the entry [i,j] the Chi-squared test statistic
for testing that the i'th visible unit
and the j'th hidden unit of the last hidden layer are independent.
"
function vishidtabs(particles::Particles)
   hidindex = length(particles)
   n = size(particles[1])[1] # number of samples
   visfreq = sum(particles[1],1)
   hidfreq = sum(particles[hidindex],1)

   chisq = zeros(length(visfreq),length(hidfreq))
   for i=eachindex(visfreq)
      for j=eachindex(hidfreq)
         a = sum(particles[1][:,i] .* particles[hidindex][:,j])
         b = visfreq[i] - a
         c = hidfreq[j] - a
         d = n - (a+b+c)
         chisq[i,j] = (a*d - b*c)^2*n/(visfreq[i]*hidfreq[j]*(n-visfreq[i])*(n-hidfreq[j]))
      end
   end

   chisq
end

function tstatistics(particles::Particles)
   # for formula see "Methodik klinischer Studien", p.40+41
   hidindex = length(particles)
   nsamples, nvisible = size(particles[1])
   nhidden = size(particles[hidindex], 2)
   t = zeros(nvisible, nhidden)
   for i = 1:nvisible
      for j = 1:nhidden
         zeromask = (particles[hidindex][:,j] .== 0)
         n1 = sum(zeromask)
         n2 = nsamples - n1
         x1 = particles[1][zeromask,i]    # group 1: hidden unit j is 0
         x2 = particles[1][!zeromask,i]   # group 2: hidden unit j is 1
         m1 = mean(x1)
         m2 = mean(x2)
         s1 = 1 / (n1 - 1) * norm(x1 - m1)
         s2 = 1 / (n2 - 1) * norm(x2 - m2)
         s12 = ((n1 - 1) * s1 + (n2 - 1) * s2) / (n1 + n2 - 2)
         t[i,j] = sqrt(n1 * n2 / (n1 + n2)) * abs(m1 - m2) / sqrt(s12)
      end
   end
   t
end

function comparecrosstab(x::Array{Float64,2}, z::Array{Float64,2})

   xfreq = samplefrequencies(x)
   zfreq = samplefrequencies(z)

   sumsqdiff = 0.0

   for key in keys(zfreq)
      sumsqdiff += (get(xfreq, key, 0) - zfreq[key])^2 / zfreq[key]
   end

   sumsqdiff
end

function sumlogprob(x,z)

   zfreq = samplefrequencies(x)

   sumprob = 0.0
   nsamples = size(x, 1)
   for i=1:nsamples
      freq = get(zfreq, vec(x[i,:]), 0)
      if freq != 0
         sumprob += log(freq)
      end
   end

   sumprob
end

function partprob(x,z,partition)
   partidxs = sort(unique(partition))

   probs = ones(size(x)[1])
   for index in partidxs
      curmask = (partition .== index)
      zfreq = BMs.samplefrequencies(z[:,curmask])

      for i=1:size(x)[1]
         probs[i] *= get(zfreq, vec(x[i,curmask]), 0)
      end
      # println(probs')
   end

   probs
end

"
Compares DBMs based on generated data (in dictionary 'modelx')
with respect to the probability of test data ('xtest'),
based on partitions of the variables obtained from
reference visible and hidden states in 'refparticles'
"
function comparedbms(modelx,refparticles::Particles,xtest)
   chires = BMs.vishidtabs(refparticles)
   maxchi = map(_ -> indmax(chires[_,:]),1:size(xtest)[2])
   comparedbms(modelx,maxchi,xtest)
end

function comparedbms(modelx,partition::Array{Int,1},xtest)
   loglik = Dict()
   for key in keys(modelx)
      loglik[key] = sum(log(BMs.partprob(xtest,modelx[key],partition)))
   end
   loglik
end

# TODO Funktionen comparedbms und partprob mit folgender Funktion ersetzen, wenn ausreichend getestet:
"
Estimates the log-likelihood of each of the given DBMs by partitioning the
visible units in blocks that are independent from each other and estimating the
probabilites for these blocks by their frequency in generated samples.
"
function haraldsloglikelihoods(dbms, x::Array{Float64,2};
      ntogenerate::Int = 100000, burnin::Int = 10)

   # Use the first DBM as reference model, which is used to identify groups of
   # input units that will be assumed to be independent when calculating the
   # probability of the training samples.
   refparticles = BMs.sampledbm(dbms[1], ntogenerate, burnin, true)

   # Matrix containing assocations of visible to hidden units in the reference model
   chisq = BMs.vishidtabs(refparticles)

   # Array containing in the j'th entry the index of the hidden unit that is
   # highest associated with the j'th visible unit/variable:
   nvariables = size(x, 2)
   assochiddenindexes = map(_ -> indmax(chisq[_,:]), 1:nvariables)

   # Set of indexes of hidden units that are highly associated with
   # a visible unit in the reference model.
   assochiddengroup = sort(unique(assochiddenindexes))

   ndbms = length(dbms)
   loglikelihoods = Array{Float64,1}(ndbms)

   ntrainingsamples = size(x, 1)

   for j = 1:ndbms
      # generate samples from j'th DBM
      generated = BMs.sampledbm(dbms[j], ntogenerate, burnin)

      pxmodel = ones(ntrainingsamples)
      for hiddenindex in assochiddengroup
         correlatedvars = (assochiddenindexes .== hiddenindex)
         genfreq = BMs.samplefrequencies(generated[:, correlatedvars])

         for i = 1:ntrainingsamples
            # The frequency of (the part of) a training sample
            # occurring in the generated samples is an estimator for the
            # probability that the model assigns to the (part of the)
            # training sample.
            pxmodelcorrelatedvars = get(genfreq, vec(x[i, correlatedvars]), 0)

            # The probabilities of independent parts are
            # multiplied to get the probability of the sample.
            pxmodel[i] *= pxmodelcorrelatedvars
         end
      end

      loglikelihoods[j] = sum(log(pxmodel))

   end

   loglikelihoods
end

function findcliques(rbm::Union{BernoulliRBM, BasicDBM},
      nparticles::Int = 10000, burnin::Int = 10)

   findcliques(vishidtabs(sampleparticles(rbm, nparticles, burnin)))
end

function findcliques(gbrbm::GaussianBernoulliRBM,
      nparticles::Int = 10000, burnin::Int = 10)

   findcliques(tstatistics(sampleparticles(gbrbm, nparticles, burnin)))
end

function findcliques(vishidstatistics::Matrix{Float64})
   nvariables = size(vishidstatistics, 1)

   # compute distances of visible units based on similarity of chi-square-statistics
   chidists = zeros(nvariables, nvariables)
   for i=1:(nvariables-1)
      for j=(i+1):nvariables
         chidists[i,j] = chidists[j,i] =
               sum((vishidstatistics[i,:] - vishidstatistics[j,:]).^2)
      end
   end

   # fill set of arrays to contain correlated variables
   cliques = Dict{Array{Int,1},Void}()
   for i = 1:nvariables

      # sort distances, first element is always zero after sorting
      # (distance to itself)
      sorteddistances = sort(vec(chidists[i,:]))

      # jumps are differences of distances
      jumps = sorteddistances[3:end] - sorteddistances[2:(end-1)]

      # maximum distance that will still be considered a neighbor is the
      # distance before the biggest jump
      maxdist = sorteddistances[indmax(jumps) + 1]

      neighmask = vec(chidists[i,:] .<= maxdist)
      if sum(neighmask) <= nvariables/2 # exclude complements of variable sets
         neighbors = (1:nvariables)[neighmask]
         cliques[neighbors] = nothing
      end
   end

   collect(keys(cliques))
end

"
Finds the best result generated in `n` tries by function `gen`
with respect to the comparison of a score , determined by function `score`.
Returns the result with the best score together with the list of all scores.
The function `gen` must be callable with no arguments and return one result,
the function `score` must take this result and return a number of type Float64.
"
function findbest(gen::Function, score::Function, n::Int;
      parallelized::Bool = false)

   if parallelized
      highestscoring = @parallel (reducehighscore) for i=1:n
         result = gen()
         resultscore = score(result)
         result, resultscore, [resultscore]
      end
      bestresult = highestscoring[1]
      scores = highestscoring[3]
   else
      scores = Array{Float64,1}(n)
      bestresult = gen()
      bestscore = score(bestresult)
      scores[1] = bestscore

      for j = 2:n
         nextresult = gen()
         nextscore = score(nextresult)
         if nextscore > bestscore
            bestresult = nextresult
            bestscore = nextscore
         end
         scores[j] = nextscore
      end
   end

   bestresult, scores
end

"
Gets two tuples of form (object, score of object, scores of all objects)
and compares the two scores contained in the second element of the tuple.
Returns the tuple
(object with highest score,
 score of object with highest score,
 array containing all scores).
"
function reducehighscore(t1::Tuple{Any, Float64, Array{Float64,1}},
      t2::Tuple{Any, Float64, Array{Float64,1}})

   if t1[2] > t2[2]
      bestobject = t1[1]
      bestscore = t1[2]
   else
      bestobject = t2[1]
      bestscore = t2[2]
   end
   bestobject, bestscore, vcat(t1[3], t2[3])
end

include("evaluating.jl")
include("monitoring.jl")

include("BMPlots.jl")

end # of module BoltzmannMachines
