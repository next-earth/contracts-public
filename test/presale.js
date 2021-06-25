const Presale = artifacts.require('Presale')
const PriceFeed = artifacts.require('PriceFeed')
const BN = require('bn.js')

contract('Presale', accounts => {
  let chainId
  let gasPrice
  beforeEach(async () => {
    chainId = await web3.eth.net.getId();
    gasPrice = new BN(await web3.eth.getGasPrice());
  })
  
  async function getBNBPrice(dollarAmount) {
    const priceFeed = await PriceFeed.deployed()
    const answer = await priceFeed.latestRoundData()
    return answer.answer.mul(new BN(dollarAmount))
  }

  it('should allow buyins with valid sigs', async () => {
    const presale = await Presale.deployed()
    const initialBalance = await presale.getBalance({from: accounts[2]});
    const merchant = await presale.merchant()
    assert( merchant && merchant === accounts[1] )
    const landsRoot = web3.utils.randomHex(32)
    const comissionPercent = 125;
    const comissionCode = '';
    const discountPercent = 80; // 8%
    const hash = await web3.utils.soliditySha3(
      {type: 'uint32', value: '1'},
      {type: 'bytes32', value: landsRoot},
      {type: 'address', value: accounts[2]},
      {type: 'uint16', value: comissionPercent},
      {type: 'string', value: comissionCode},
      {type: 'uint16', value: discountPercent},
    );
    let sig = await web3.eth.sign(hash, accounts[1])
    sig = sig.substr(0, 130) + (sig.substr(130) == '00' ? '1b' : '1c')
    const bnbPrice = (await getBNBPrice('150')).div(new BN('100')).mul(new BN('92'))
    console.log(bnbPrice.toString(10))
    await presale.buyPack(1, landsRoot, comissionPercent, comissionCode, 
      discountPercent, sig, {from: accounts[2], value: bnbPrice})
    const balance = await presale.getBalance({from: accounts[2]})
    assert(balance.eq(initialBalance.add(new BN('15000'))))
  })

  it('handle discount addresses properly', async () => {
    const presale = await Presale.deployed()
    assert.equal((await presale.isDiscounted.call({from: accounts[1]})), false)
    await presale.setDiscount(accounts[1], true, { from: accounts[0] })
    assert.equal((await presale.isDiscounted.call({from: accounts[1]})), true)
  })

  it('only allow one buyin per wallet', async () => {
    const presale = await Presale.deployed()
    const initialBalance = await presale.getBalance({from: accounts[2]});
    const merchant = await presale.merchant()
    assert( merchant && merchant === accounts[1] )
    const landsRoot = web3.utils.randomHex(32)
    const comissionPercent = 0;
    const discountPercent = 0;
    const comissionCode = '';
    const hash = await web3.utils.soliditySha3(
      {type: 'uint32', value: '1'},
      {type: 'bytes32', value: landsRoot},
      {type: 'address', value: accounts[2]},
      {type: 'uint16', value: comissionPercent * 10},
      {type: 'string', value: comissionCode},
      {type: 'uint16', value: discountPercent},
    );
    let sig = await web3.eth.sign(hash, accounts[1])
    sig = sig.substr(0, 130) + (sig.substr(130) == '00' ? '1b' : '1c')
    try {
    await presale.buyPack(1, landsRoot, comissionPercent, comissionCode, 
      discountPercent, sig, {from: accounts[2], value: await getBNBPrice('150')})
      return false
    } catch (e) {
      assert.equal(e.reason, 'only one purchase per wallet')
      return true
    }
  })

  it('reject buyins with hijacked sigs', async () => {
    const presale = await Presale.deployed()
    const merchant = await presale.merchant()
    assert( merchant && merchant === accounts[1] )
    const landsRoot = web3.utils.randomHex(32)
    const comissionPercent = 0;
    const discountPercent = 0;
    const comissionCode = '';
    const hash = await web3.utils.soliditySha3(
      {type: 'uint32', value: '1'},
      {type: 'bytes32', value: landsRoot},
      {type: 'address', value: accounts[3]},
      {type: 'uint16', value: comissionPercent * 10},
      {type: 'string', value: comissionCode},
      {type: 'uint16', value: discountPercent},
    );
    let sig = await web3.eth.sign(hash, accounts[1])
    sig = sig.substr(0, 130) + (sig.substr(130) == '00' ? '1b' : '1c')
    try {
      await presale.buyPack(1, landsRoot, comissionPercent, comissionCode,
        discountPercent, sig, {from: accounts[2], value: await getBNBPrice('150')})
      return false
    } catch (e) {
      assert.equal(e.reason, 'invalid merchant signature')
      return true
    }
  })

  it('reject buyins with not enough funds', async () => {
    const presale = await Presale.deployed()
    const merchant = await presale.merchant()
    assert( merchant && merchant === accounts[1] )
    const landsRoot = web3.utils.randomHex(32)
    const comissionPercent = 0;
    const discountPercent = 0;
    const comissionCode = '';
    const hash = await web3.utils.soliditySha3(
      {type: 'uint32', value: '1'},
      {type: 'bytes32', value: landsRoot},
      {type: 'address', value: accounts[3]},
      {type: 'uint16', value: comissionPercent * 10},
      {type: 'string', value: comissionCode},
      {type: 'uint16', value: discountPercent},
    );
    let sig = await web3.eth.sign(hash, accounts[1])
    sig = sig.substr(0, 130) + (sig.substr(130) == '00' ? '1b' : '1c')
    try {
    const bnbPrice = await getBNBPrice('1')
    await presale.buyPack(1, landsRoot, comissionPercent, comissionCode, 
      discountPercent, sig, {from: accounts[3], value: bnbPrice.div(new BN('10'))}) // one zero less!
      return false
    } catch (e) {
      assert.equal(e.reason, 'not enough funds')
      return true
    }
  })

  it('prevents owner to claim charity + comissons', async () => {
    const presale = await Presale.deployed()
    const owner = accounts[0]
    const initialBalance = new BN(await web3.eth.getBalance(owner))
    const contractBalance = new BN(await web3.eth.getBalance(presale.address))
    const charityPool = new BN(await presale.charityBalance())
    const comissionPool = new BN(await presale.comissionPool())
    const allowedAmount = contractBalance.sub(charityPool).sub(comissionPool)
    
    const tx = await presale.claimSale({from: owner})
    const gasUsed = new BN(tx.receipt.gasUsed)
    const gasPaid = gasUsed.mul(gasPrice)
    const newBalance = new BN(await web3.eth.getBalance(owner))
    const ethersReceived = newBalance.sub(initialBalance)
    assert(ethersReceived.lte(allowedAmount))
  })

  it('reject attacker of claiming charity pool', async () => {
    const presale = await Presale.deployed()
    const charityAddress = accounts[7]
    try {
      await presale.claimCharity({from: accounts[6]})
      return false
    } catch (e) {
      assert.equal(e.reason, 'reserved for charity')
    }
  })

  it('allows charity address to claim charity pool', async () => {
    const presale = await Presale.deployed()
    const charityAddress = accounts[7]
    const initialBalance = new BN(await web3.eth.getBalance(charityAddress))
    const charityBalance = await presale.charityBalance()
    const tx = await presale.claimCharity({from: charityAddress})
    const gasUsed = new BN(tx.receipt.gasUsed)
    const gasPaid = gasUsed.mul(gasPrice)
    const newBalance = new BN(await web3.eth.getBalance(charityAddress))
    const ethersReceived = newBalance.sub(initialBalance)
    const targetBalance = charityBalance.sub(gasPaid)
    assert(ethersReceived.eq(targetBalance))
  })

  it('reject comission claim with invalid sig', async () => {
    const presale = await Presale.deployed()
    const comissionCode = 'any code is valid as long as its signed'
    const comissionAmount = new BN('10000000000000')
    const comissionAddress = accounts[5]
    const hash = await web3.utils.soliditySha3(
      {type: 'string', value: comissionCode},
      {type: 'uint256', value: comissionAmount.add(new BN('1'))},
      {type: 'address', value: comissionAddress},
    );
    let sig = await web3.eth.sign(hash, accounts[1])
    sig = sig.substr(0, 130) + (sig.substr(130) == '00' ? '1b' : '1c')
    try { 
    const tx = await presale.claimComission(comissionCode,
      comissionAmount, sig, {from: comissionAddress})
    } catch (e) {
      assert.equal(e.reason, 'invalid merchant signature')
    }
  })

  it('allows claiming comission with correct sig', async () => {
    const presale = await Presale.deployed()
    const comissionCode = 'any code is valid as long as its signed'
    const comissionAmount = new BN('10000000000000')
    const comissionAddress = accounts[5]
    const hash = await web3.utils.soliditySha3(
      {type: 'string', value: comissionCode},
      {type: 'uint256', value: comissionAmount},
      {type: 'address', value: comissionAddress},
    );
    let sig = await web3.eth.sign(hash, accounts[1])
    sig = sig.substr(0, 130) + (sig.substr(130) == '00' ? '1b' : '1c')
    
    const initialBalance = new BN(await web3.eth.getBalance(comissionAddress))
    const tx = await presale.claimComission(comissionCode,
      comissionAmount, sig, {from: comissionAddress})
    const gasUsed = new BN(tx.receipt.gasUsed)
    const gasPaid = gasUsed.mul(gasPrice)
    const newBalance = new BN(await web3.eth.getBalance(comissionAddress))
    const ethersReceived = newBalance.sub(initialBalance)
    const targetBalance = comissionAmount.sub(gasPaid)
    assert(ethersReceived.eq(targetBalance))
  })

})
