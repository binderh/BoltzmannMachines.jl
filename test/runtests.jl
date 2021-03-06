using Base.Test

import BoltzmannMachines
const BMs = BoltzmannMachines

include("BMTest.jl")

@test isapprox(BMs.bernoulliloglikelihoodbaserate(10),
      BMs.bernoulliloglikelihoodbaserate(rand([0.0 1.0], 10000, 10)),
      atol = 0.002)

# Test exact loglikelihood of a baserate RBM
# vs the calculated loglikelihoodbaserate
x = rand([0.0 0.0 0.0 1.0 1.0], 100, 10);
@test isapprox(BMTest.bgrbmexactloglikelihoodvsbaserate(x, 10), 0, atol = 1e-10)
@test isapprox(BMTest.rbmexactloglikelihoodvsbaserate(x, 10), 0, atol = 1e-10)
x = rand(100, 10) + randn(100, 10);
@test isapprox(BMTest.gbrbmexactloglikelihoodvsbaserate(x, 10), 0, atol = 1e-10)


nvisible = 10
nhidden = 10
bgrbm = BMs.BernoulliGaussianRBM(zeros(nvisible, nhidden), rand(nvisible), ones(nhidden));
@test isapprox(BMs.logpartitionfunction(bgrbm, 1.0),
      BMs.exactlogpartitionfunction(bgrbm))

# Test exact computation of log partition function of DBM:
# Compare inefficient simple implementation with more efficient one that
# sums out layers analytically.
nhiddensvecs = Array[[5;4;6;3], [5;6;7], [4;4;2;4;3], [4;3;2;2;3;2]];
for i = 1:length(nhiddensvecs)
   dbm = BMTest.randdbm(nhiddensvecs[i]);
   @test isapprox(BMs.exactlogpartitionfunction(dbm),
         BMTest.exactlogpartitionfunctionwithoutsummingout(dbm))
end

for nunits in Array[[10;5;4], [20;5;4;2], [4;2;2;3;2]]
   BMTest.testsummingoutforexactloglikelihood(nunits)
end

BMTest.testdbmjoining()

BMTest.testloglikelihood_b2brbm()

# run examples
include("examples.jl")