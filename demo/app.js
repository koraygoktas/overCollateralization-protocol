const ADDR = {
  pool: "0x136Cd160Ac2587277087b721315a8A5Ff72f5D83",
  collateralToken: "0x3e7E51EDb16A5D7Bb15fc7dF3c2B8C62fbCa523d",
  debtToken: "0xC981186F2978C8079488951a31c230839aa4CeB8",
  collateralOracle: "0xc8e66EB33cfeF168Ff8580265bDfB98e16F3272c",
  debtOracle: "0x1F87B0aACcE8311c2c26788e2914612f84f1E5E2",
};
const SEPOLIA_CHAIN_ID_HEX = "0xaa36a7";

const POOL_ABI = [
  "function deposit(uint256 amount)",
  "function withdraw(uint256 amount)",
  "function borrow(uint256 amount)",
  "function repay(uint256 amount)",
  "function liquidate(address user, uint256 debtToCover)",
  "function getRequiredCollateralRatio(address user) view returns (uint256)",
  "function getMaxBorrowLimit(address user) view returns (uint256)",
  "function collateralBalances(address) view returns (uint256)",
  "function debtBalances(address) view returns (uint256)",
  "function reputationScore(address) view returns (uint256)",
  "function INITIAL_RATIO() view returns (uint256)",
  "function FLOOR_RATIO() view returns (uint256)",
  "error InsufficientCollateral()",
  "error InsufficientBalance()",
  "error ZeroAmount()",
  "error BorrowLimitExceeded()",
  "error PositionIsHealthy()"
];

const ERC20_ABI = [
  "function balanceOf(address) view returns (uint256)",
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function mint(address to, uint256 amount)"
];

const ORACLE_ABI = [
  "function getPrice() view returns (uint256)",
  "function setPrice(uint256 newPrice)",
  "function owner() view returns (address)"
];

let provider, signer, userAddress;
let pool, collateralToken, debtToken, collateralOracle, debtOracle;

const $ = (id) => document.getElementById(id);

function log(msg, kind = "") {
  const box = $("logBox");
  if (box.children.length === 1 && box.children[0].textContent === "No transactions yet.") {
    box.innerHTML = "";
  }
  const line = document.createElement("div");
  line.className = "log-line " + kind;
  const time = new Date().toLocaleTimeString("en-US");
  line.innerHTML = `<span class="t">${time}</span>${msg}`;
  box.prepend(line);
}

function fmt(bigVal, decimals = 18, maxFrac = 3) {
  try {
    const s = ethers.formatUnits(bigVal, decimals);
    return Number(s).toLocaleString("en-US", { maximumFractionDigits: maxFrac });
  } catch (e) {
    return "—";
  }
}

function extractError(e) {
  if (e?.reason) return e.reason;
  if (e?.shortMessage) return e.shortMessage;
  if (e?.info?.error?.message) return e.info.error.message;
  if (e?.message) return e.message.slice(0, 120);
  return "Unknown error";
}

$("connectBtn").addEventListener("click", connectWallet);

async function connectWallet() {
  if (!window.ethereum) {
    log("MetaMask not found. Please install the MetaMask extension and refresh the page.", "err");
    alert("MetaMask not found. Please install the MetaMask extension and refresh the page.");
    return;
  }
  try {
    await window.ethereum.request({ method: "eth_requestAccounts" });
    await ensureSepolia();

    provider = new ethers.BrowserProvider(window.ethereum);
    signer = await provider.getSigner();
    userAddress = await signer.getAddress();

    pool = new ethers.Contract(ADDR.pool, POOL_ABI, signer);
    collateralToken = new ethers.Contract(ADDR.collateralToken, ERC20_ABI, signer);
    debtToken = new ethers.Contract(ADDR.debtToken, ERC20_ABI, signer);
    collateralOracle = new ethers.Contract(ADDR.collateralOracle, ORACLE_ABI, signer);
    debtOracle = new ethers.Contract(ADDR.debtOracle, ORACLE_ABI, signer);

    $("addrChip").textContent = userAddress.slice(0, 6) + "…" + userAddress.slice(-4);
    $("walletInfo").style.display = "block";
    $("connectBtn").textContent = "Connected";
    $("connectBtn").disabled = true;
    $("lockedView").style.display = "none";
    $("app").style.display = "block";
    $("poolAddrFooter").textContent = ADDR.pool;
    $("etherscanLink").href = "https://sepolia.etherscan.io/address/" + ADDR.pool;

    log("Wallet connected: " + userAddress, "ok");
    await refreshAll();

    window.ethereum.on("accountsChanged", () => window.location.reload());
    window.ethereum.on("chainChanged", () => window.location.reload());
  } catch (e) {
    log("Connection error: " + extractError(e), "err");
  }
}

async function ensureSepolia() {
  const currentChainId = await window.ethereum.request({ method: "eth_chainId" });
  if (currentChainId === SEPOLIA_CHAIN_ID_HEX) return;
  try {
    await window.ethereum.request({
      method: "wallet_switchEthereumChain",
      params: [{ chainId: SEPOLIA_CHAIN_ID_HEX }],
    });
  } catch (switchError) {
    if (switchError.code === 4902) {
      await window.ethereum.request({
        method: "wallet_addEthereumChain",
        params: [{
          chainId: SEPOLIA_CHAIN_ID_HEX,
          chainName: "Sepolia",
          nativeCurrency: { name: "Sepolia ETH", symbol: "ETH", decimals: 18 },
          rpcUrls: ["https://ethereum-sepolia-rpc.publicnode.com"],
          blockExplorerUrls: ["https://sepolia.etherscan.io"],
        }],
      });
    } else {
      throw switchError;
    }
  }
}

async function refreshAll() {
  if (!userAddress) return;
  try {
    const [
      colWalletBal, debtWalletBal,
      colPoolBal, debtPoolBal,
      reputation, requiredRatio, maxLimit,
      initialRatio, floorRatio,
      colPrice, debtPrice
    ] = await Promise.all([
      collateralToken.balanceOf(userAddress),
      debtToken.balanceOf(userAddress),
      pool.collateralBalances(userAddress),
      pool.debtBalances(userAddress),
      pool.reputationScore(userAddress),
      pool.getRequiredCollateralRatio(userAddress),
      pool.getMaxBorrowLimit(userAddress),
      pool.INITIAL_RATIO(),
      pool.FLOOR_RATIO(),
      collateralOracle.getPrice(),
      debtOracle.getPrice(),
    ]);

    $("colWalletBal").textContent = fmt(colWalletBal) + " mCOL";
    $("debtWalletBal").textContent = fmt(debtWalletBal) + " mDEBT";
    $("colPoolBal").textContent = fmt(colPoolBal) + " mCOL";
    $("debtPoolBal").textContent = fmt(debtPoolBal) + " mDEBT";
    $("repScore").textContent = reputation.toString();
    $("maxLimit").innerHTML = fmt(maxLimit) + " <small>mDEBT</small>";

    const ratioPct = Number(ethers.formatUnits(requiredRatio, 18)) * 100;
    const initialPct = Number(ethers.formatUnits(initialRatio, 18)) * 100;
    const floorPct = Number(ethers.formatUnits(floorRatio, 18)) * 100;
    $("ratioValue").textContent = ratioPct.toFixed(1);

    const span = initialPct - floorPct;
    const posPct = span > 0 ? Math.min(100, Math.max(0, ((initialPct - ratioPct) / span) * 100)) : 0;
    $("gaugeFill").style.width = posPct + "%";
    $("gaugeMarker").style.left = posPct + "%";

    $("colPrice").textContent = "$" + Number(ethers.formatUnits(colPrice, 18)).toLocaleString("en-US", {maximumFractionDigits: 4});
    $("debtPrice").textContent = "$" + Number(ethers.formatUnits(debtPrice, 18)).toLocaleString("en-US", {maximumFractionDigits: 4});

    const collateralValue = (colPoolBal * colPrice) / (10n ** 18n);
    const debtValue = (debtPoolBal * debtPrice) / (10n ** 18n);
    const requiredValue = (debtValue * requiredRatio) / (10n ** 18n);
    const isHealthy = debtPoolBal === 0n || collateralValue >= requiredValue;

    const badge = $("statusBadge");
    const healthText = $("healthText");
    if (debtPoolBal === 0n) {
      badge.className = "status-badge status-none";
      badge.textContent = "No debt";
      healthText.textContent = "—";
    } else if (isHealthy) {
      badge.className = "status-badge status-healthy";
      badge.textContent = "Healthy";
      healthText.textContent = "Healthy";
      healthText.style.color = "var(--sage)";
    } else {
      badge.className = "status-badge status-risky";
      badge.textContent = "Open to Liquidation";
      healthText.textContent = "Risky";
      healthText.style.color = "var(--brick)";
    }
  } catch (e) {
    log("Data read error: " + extractError(e), "err");
  }
}

async function runTx(label, fn) {
  try {
    log(label + " sending...");
    const tx = await fn();
    log(label + " awaiting confirmation: " + tx.hash.slice(0, 10) + "…");
    await tx.wait();
    log(label + " successful ✓", "ok");
    await refreshAll();
  } catch (e) {
    log(label + " failed: " + extractError(e), "err");
  }
}

$("mintColBtn").addEventListener("click", () => {
  runTx("Mint test mCOL", () =>
    collateralToken.mint(userAddress, ethers.parseUnits("500", 18))
  );
});

$("depositBtn").addEventListener("click", async () => {
  const val = $("depositInput").value;
  if (!val || Number(val) <= 0) return log("Enter a valid amount.", "err");
  const amount = ethers.parseUnits(val, 18);
  try {
    log("Sending approval...");
    const approveTx = await collateralToken.approve(ADDR.pool, amount);
    await approveTx.wait();
    log("Approval completed ✓", "ok");
    await runTx("Depositing collateral", () => pool.deposit(amount));
    $("depositInput").value = "";
  } catch (e) {
    log("Deposit failed: " + extractError(e), "err");
  }
});

$("withdrawBtn").addEventListener("click", () => {
  const val = $("withdrawInput").value;
  if (!val || Number(val) <= 0) return log("Enter a valid amount.", "err");
  runTx("Withdrawing collateral", () => pool.withdraw(ethers.parseUnits(val, 18)))
    .then(() => { $("withdrawInput").value = ""; });
});

$("borrowBtn").addEventListener("click", () => {
  const val = $("borrowInput").value;
  if (!val || Number(val) <= 0) return log("Enter a valid amount.", "err");
  runTx("Borrowing debt", () => pool.borrow(ethers.parseUnits(val, 18)))
    .then(() => { $("borrowInput").value = ""; });
});

$("repayBtn").addEventListener("click", async () => {
  const val = $("repayInput").value;
  if (!val || Number(val) <= 0) return log("Enter a valid amount.", "err");
  const amount = ethers.parseUnits(val, 18);
  try {
    log("Sending approval...");
    const approveTx = await debtToken.approve(ADDR.pool, amount);
    await approveTx.wait();
    log("Approval completed ✓", "ok");
    await runTx("Repaying debt", () => pool.repay(amount));
    $("repayInput").value = "";
  } catch (e) {
    log("Repayment failed: " + extractError(e), "err");
  }
});

$("liqBtn").addEventListener("click", async () => {
  const addr = $("liqAddress").value.trim();
  const val = $("liqAmount").value;
  if (!ethers.isAddress(addr)) return log("Enter a valid address.", "err");
  if (!val || Number(val) <= 0) return log("Enter a valid amount.", "err");
  const amount = ethers.parseUnits(val, 18);
  try {
    log("Sending approval...");
    const approveTx = await debtToken.approve(ADDR.pool, amount);
    await approveTx.wait();
    log("Approval completed ✓", "ok");
    await runTx("Liquidation", () => pool.liquidate(addr, amount));
  } catch (e) {
    log("Liquidation failed: " + extractError(e), "err");
  }
});

$("setColPriceBtn").addEventListener("click", () => {
  const val = $("colPriceInput").value;
  if (!val || Number(val) < 0) return log("Enter a valid price.", "err");
  runTx("Updating collateral price", () => collateralOracle.setPrice(ethers.parseUnits(val, 18)));
});

$("setDebtPriceBtn").addEventListener("click", () => {
  const val = $("debtPriceInput").value;
  if (!val || Number(val) < 0) return log("Enter a valid price.", "err");
  runTx("Updating debt price", () => debtOracle.setPrice(ethers.parseUnits(val, 18)));
});
