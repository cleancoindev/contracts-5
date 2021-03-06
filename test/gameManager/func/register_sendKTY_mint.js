const expect = require('chai').expect;

exports.test = (f, amount) => {
  const context = f;

  it('registers 40 users', async () => {
    let users = 40;

    for(let i = 1; i <= users; i++){
          expect(await proxy.execute('Register', setMessage(register, 'register', []), {
            from: accounts[i]
          }).should.be.fulfilled;

          let isRegistered = await register.isRegistered(accounts[i]);
      } 
  })

  it('sends 30000 KTYs to 40 users', async () => {
    let amountKTY = 30000;
    let users = 40;

    for(let i = 1; i <= users; i++){
          await kittieFightToken.transfer(accounts[i], web3.utils.toWei(String(amountKTY)), {
              from: accounts[0]}).should.be.fulfilled;

          await kittieFightToken.approve(endowmentFund.address, web3.utils.toWei(String(amountKTY)) , { from: accounts[i] }).should.be.fulfilled;

          let userBalance = await kittieFightToken.balanceOf(accounts[i]);
      } 
  })

  it('mints kitties for 2 users', async () => {
    let users = 8;

    let kitties = [324, 1001, 1555108, 1267904, 454545, 333, 6666, 2111];
      let cividIds = [1, 2, 3, 4, 5, 6, 7, 8];

      await cryptoKitties.mint(accounts[1], kitties[0], { from: accounts[0] }).should.be.fulfilled;
      await cryptoKitties.approve(kittieHell.address, kitties[0], { from: accounts[1] }).should.be.fulfilled;
      await proxy.execute('Register', setMessage(register, 'verifyAccount', [cividIds[0]]), { from: accounts[1]}).should.be.fulfilled;

      console.log(`New Player ${accounts[1]} with Kitty ${kitties[0]}`);

      await cryptoKitties.mint(accounts[2], kitties[1], { from: accounts[0] }).should.be.fulfilled;
      await cryptoKitties.approve(kittieHell.address, kitties[1], { from: accounts[2] }).should.be.fulfilled;
      await proxy.execute('Register', setMessage(register, 'verifyAccount', [cividIds[1]]), { from: accounts[2]}).should.be.fulfilled;

      console.log(`New Player ${accounts[2]} with Kitty ${kitties[1]}`);
  })
};
