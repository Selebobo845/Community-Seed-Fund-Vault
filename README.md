# 🌱 Community Seed Fund Vault
A decentralized smart contract that enables farmers to access shared community funds for purchasing seeds and repay after harvest. Built on the Stacks blockchain using Clarity smart contracts.

## 🚀 Features

- 🌾 **Farmer Registration**: Farmers can register with their details
- 💰 **Community Contributions**: Anyone can contribute to the shared fund
- 📋 **Loan Requests**: Registered farmers can request loans for seeds
- ✅ **Loan Approval**: Contract owner approves legitimate loan requests
- 💳 **Repayment System**: Farmers repay loans with interest after harvest
- 📊 **Transparent Tracking**: All transactions and balances are publicly viewable
- ⚡ **Emergency Controls**: Owner can manage interest rates and emergency withdrawals

## 🛠️ Contract Functions

### Public Functions

#### Farmer Management
- `register-farmer(name, location)` - Register as a farmer
- `request-loan(amount)` - Request a loan for seeds
- `repay-loan(loan-id)` - Repay an approved loan with interest

#### Community Contributions
- `contribute-to-fund(amount)` - Add STX to the shared fund

#### Owner Functions
- `approve-loan(loan-id)` - Approve a farmer's loan request
- `update-interest-rate(new-rate)` - Update the interest rate percentage
- `update-loan-duration(new-duration)` - Update loan duration in blocks
- `emergency-withdraw(amount)` - Emergency fund withdrawal

### Read-Only Functions

- `get-fund-balance()` - Get current fund balance
- `get-loan-info(loan-id)` - Get loan details
- `get-farmer-info(farmer)` - Get farmer registration details
- `get-contributor-info(contributor)` - Get contributor statistics
- `get-interest-rate()` - Get current interest rate
- `get-loan-duration()` - Get loan duration in blocks
- `is-loan-overdue(loan-id)` - Check if loan is overdue
- `calculate-repayment-amount(loan-id)` - Calculate total repayment amount
- `get-farmer-active-loans(farmer)` - Get farmer's active loan count

## 📋 Usage Instructions

### 1. Setup with Clarinet

```bash
clarinet new community-seed-fund
cd community-seed-fund
# Replace the default contract with the Community-Seed-Fund-Vault.clar
clarinet check
```

✅ **Contract Status**: Compilation verified with `clarinet check`

### 2. Deploy the Contract

```bash
clarinet deploy --testnet
```

### 3. Farmer Registration

```clarity
(contract-call? .Community-Seed-Fund-Vault register-farmer "John Doe" "Rural Farm District")
```

### 4. Community Contribution

```clarity
(contract-call? .Community-Seed-Fund-Vault contribute-to-fund u1000000)
```

### 5. Request a Loan

```clarity
(contract-call? .Community-Seed-Fund-Vault request-loan u500000)
```

### 6. Approve Loan (Owner Only)

```clarity
(contract-call? .Community-Seed-Fund-Vault approve-loan u1)
```

### 7. Repay Loan

```clarity
(contract-call? .Community-Seed-Fund-Vault repay-loan u1)
```

## 🔧 Configuration

- **Default Interest Rate**: 10%
- **Default Loan Duration**: 4320 blocks (~30 days)
- **Contract Owner**: Deployer address

## 📊 Example Workflow

1. **Community Setup**: Community members contribute STX to build the fund
2. **Farmer Registration**: Farmers register with their details
3. **Seed Season**: Farmers request loans for purchasing seeds
4. **Loan Approval**: Contract owner reviews and approves legitimate requests
5. **Fund Distribution**: Approved loans are automatically transferred to farmers
6. **Harvest Season**: Farmers repay loans with interest after successful harvest
7. **Fund Growth**: Repaid amounts increase the fund for future seasons

## 🔒 Security Features

- Only registered farmers can request loans
- Owner approval required for all loans
- Interest calculations prevent fund depletion
- Emergency withdrawal for fund protection
- Transparent tracking of all transactions

## 💡 Technical Details

- **Blockchain**: Stacks
- **Language**: Clarity (186 lines)
- **Token**: STX (Stacks)
- **Interest**: 10% default, configurable by owner
- **Loan Duration**: 4320 blocks (~30 days)
- **Repayment**: Principal + Interest
- **Compilation**: ✅ Verified with `clarinet check`

## 🤝 Contributing

This contract is designed to be simple and secure for community use. For improvements or bug reports, please submit issues and pull requests.

## 📄 License

Open source - built for community empowerment and agricultural development.
