module BMTest

using Base.Test
import BoltzmannMachines
const BMs = BoltzmannMachines

function createsamples(nsamples::Int, nvariables::Int, samerate=0.7)
   x = round.(rand(nsamples,nvariables))
   samerange = 1:round(Int, samerate*nsamples)
   x[samerange,3] = x[samerange,2] = x[samerange,1]
   x = x[randperm(nsamples),:] # shuffle lines
   x
end

function randrbm(nvisible, nhidden, factorw = 1.0, factora = 1.0, factorb = 1.0)
   w = factorw*randn(nvisible, nhidden)
   a = factora*rand(nvisible)
   b = factorb*(0.5 - rand(nhidden))
   BMs.BernoulliRBM(w, a, b)
end

function randgbrbm(nvisible, nhidden, factorw = 1.0, factora = 1.0, factorb = 1.0, factorsd = 1.0)
   w = factorw*randn(nvisible, nhidden)
   a = factora*rand(nvisible)
   b = factorb*ones(nhidden)
   sd = factorsd*ones(nvisible)
   BMs.GaussianBernoulliRBM(w, a, b, sd)
end

function randbgrbm(nvisible, nhidden, factorw = 1.0, factora = 1.0, factorb = 1.0)
   w = factorw*randn(nvisible, nhidden)
   a = factora*rand(nvisible)
   b = factorb*ones(nhidden)
   BMs.BernoulliGaussianRBM(w, a, b)
end

function randdbm(nunits)
   nrbms = length(nunits) - 1
   dbm = BMs.BasicDBM(nrbms)
   for i = 1:nrbms
      dbm[i] = randrbm(nunits[i], nunits[i+1])
   end
   dbm
end

function logit(p::Array{Float64})
   log.(p./(1-p))
end

function rbmexactloglikelihoodvsbaserate(x::Matrix{Float64}, nhidden::Int)
   a = logit(vec(mean(x,1)))
   nvisible = length(a)
   rbm = BMs.BernoulliRBM(zeros(nvisible, nhidden), a, ones(nhidden))
   baserate = BMs.bernoulliloglikelihoodbaserate(x)
   exactloglik = BMs.loglikelihood(rbm, x, BMs.exactlogpartitionfunction(rbm))
   baserate - exactloglik
end

function bgrbmexactloglikelihoodvsbaserate(x::Matrix{Float64}, nhidden::Int)
   a = logit(vec(mean(x,1)))
   nvisible = length(a)
   bgrbm = BMs.BernoulliGaussianRBM(zeros(nvisible, nhidden), a, ones(nhidden))
   baserate = BMs.bernoulliloglikelihoodbaserate(x)
   exactloglik = BMs.loglikelihood(bgrbm, x, BMs.exactlogpartitionfunction(bgrbm))
   baserate - exactloglik
end

# TODO funzt nicht
function gbrbmexactloglikelihoodvsbaserate(x::Matrix{Float64}, nhidden::Int)
   a = vec(mean(x,1))
   nvisible = length(a)
   sd = vec(std(x,1))
   gbrbm = BMs.GaussianBernoulliRBM(zeros(nvisible, nhidden), a, ones(nhidden), sd)
   baserate = BMs.gaussianloglikelihoodbaserate(x)
   exactloglik = BMs.loglikelihood(gbrbm, x, BMs.exactlogpartitionfunction(gbrbm))
   baserate - exactloglik
end


"
Calculates the exact value for the partition function and an estimate with AIS
and return the difference between the logs of the two values
for a given RBM.
"
function aisvsexact(rbm::BMs.AbstractRBM, ntemperatures::Int = 100,
      nparticles::Int = 100)

   # Test log partition funtion estimation vs exact calculation
   exact = BMs.exactlogpartitionfunction(rbm)
   impweights = BMs.aisimportanceweights(rbm,
         ntemperatures = ntemperatures, nparticles = nparticles)
   r = mean(impweights)
   estimated = BMs.logpartitionfunction(rbm, r)
   println("Range of 2 * sd aroung AIS-estimated log partition function")
   println(BMs.aisprecision(impweights, 2.0))
   println("Difference between exact log partition function and AIS-estimated one")
   println("in percent of log of exact value")
   println((exact - estimated)/exact*100)
end

function aisvsexact(dbm::BMs.BasicDBM, ntemperatures = 100, nparticles = 100)
   nrbms = length(dbm)

   impweights = BMs.aisimportanceweights(dbm, ntemperatures = ntemperatures,
      nparticles = nparticles)

   r = mean(impweights)
   println("Range of 2 * sd aroung AIS-estimated log partition function")
   println(BMs.aisprecision(impweights, 2.0))
   exact = BMs.exactlogpartitionfunction(dbm)
   estimated = BMs.logpartitionfunction(dbm, r)
   println("Difference between exact log partition function and AIS-estimated one")
   println("in percent of log of exact value")
   println((exact - estimated)/exact*100)
   # TODO loglikelihood base-rate vs loglikelihood dbm
end

function exactlogpartitionfunctionwithoutsummingout(dbm::BMs.BasicDBM)
   nlayers = length(dbm) + 1
   u = BMs.initcombination(dbm)
   z = 0.0
   while true
      z += exp(-BMs.energy(dbm, u))
      BMs.next!(u) || break
   end
   log(z)
end

function testsummingoutforexactloglikelihood(nunits::Vector{Int})
   x = BMTest.createsamples(1000, nunits[1]);
   dbm = BMs.stackrbms(x, nhiddens = nunits[2:end],
         epochs = 50, predbm = true, learningrate = 0.001);
   dbm = BMs.traindbm!(dbm, x,
         learningrates = [0.02*ones(10); 0.01*ones(10); 0.001*ones(10)],
         epochs = 30);
   logz = BMs.exactlogpartitionfunction(dbm)
   @test isapprox(BMs.exactloglikelihood(dbm, x, logz),
         exactloglikelihoodwithoutsummingout(dbm, x, logz))
end

function exactloglikelihoodwithoutsummingout(dbm::BMs.BasicDBM, x::Array{Float64,2},
      logz = BMs.exactlogpartitionfunction(dbm))

   nsamples = size(x,1)
   nlayers = length(dbm) + 1

   u = BMs.initcombination(dbm)
   logp = 0.0
   for j = 1:nsamples
      u[1] = vec(x[j,:])

      p = 0.0
      while true
         p += exp(-BMs.energy(dbm, u))

         # next combination of hidden nodes' activations
         BMs.next!(u[2:end]) || break
      end

      logp += log(p)
   end

   logp /= nsamples
   logp -= logz
   logp
end


function testdbmjoining()
   dbm1 = BMTest.randdbm([5;4;3])
   dbm2 = BMTest.randdbm([4;5;2])
   dbm3 = BMTest.randdbm([6;7;8])

   exactlogpartitionfunction1 = BMs.exactlogpartitionfunction(dbm1)
   exactlogpartitionfunction2 = BMs.exactlogpartitionfunction(dbm2)
   exactlogpartitionfunction3 = BMs.exactlogpartitionfunction(dbm3)

   jointdbm1 = BMs.joindbms(BMs.BasicDBM[dbm1, dbm2])
   # Test use of visibleindexes
   indexes = randperm(15)

   jointdbm2 = BMs.joindbms(BMs.BasicDBM[dbm1, dbm2, dbm3],
            [indexes[1:5], indexes[6:9], indexes[10:15]])

   @test isapprox(
               exactlogpartitionfunction1 + exactlogpartitionfunction2,
               BMs.exactlogpartitionfunction(jointdbm1))

   @test isapprox(
            exactlogpartitionfunction1 + exactlogpartitionfunction2 +
                  exactlogpartitionfunction3,
            BMs.exactlogpartitionfunction(jointdbm2))
end


"
Tests whether the log-likelihood of Binomial2BernoulliRBMs is approximately
equal to the empirical loglikelihood of data generated by the models, and whether
the partition function estimated by AIS is near the exact value.
"
function testloglikelihood_b2brbm()
   x1 = BMTest.createsamples(100, 4) + BMTest.createsamples(100, 4)
   x2 = BMTest.createsamples(100, 4)
   x = hcat(x1, x2)
   b2brbm = BMs.fitrbm(x1, rbmtype = BMs.Binomial2BernoulliRBM, epochs = 30,
         nhidden = 4, learningrate = 0.001)
   rbm = BMs.fitrbm(x2, rbmtype = BMs.BernoulliRBM, epochs = 30,
         nhidden = 3, learningrate = 0.001)

   emploglik = BMs.empiricalloglikelihood(b2brbm, x1, 1000000)
   estloglik = BMs.loglikelihood(b2brbm, x1)
   exactloglik = BMs.exactloglikelihood(b2brbm, x1)
   @test abs((exactloglik - emploglik)/exactloglik) < 0.01
   @test abs((exactloglik - estloglik)/exactloglik) < 0.01
end

end # of module
