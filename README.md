#  Microgrid Energy Sharing for Rural Communities

A blockchain-based peer-to-peer renewable energy sharing platform built on Stacks, empowering rural communities with affordable and reliable electricity access through decentralized energy trading.

## 🌟 Features

- 🔋 **Smart Meter Integration** - Record and track energy production/consumption
- 💱 **P2P Energy Trading** - Direct energy transactions between community members
- 💰 **Micro-payments** - Automated settlement using STX tokens
- 🏆 **Reputation System** - Build trust through verified energy trades
- 🌱 **Renewable Energy Incentives** - Bonus rewards for green energy producers
- 📍 **Location-based Trading** - Trade within your local community
- ⏸️ **Emergency Controls** - Admin pause/resume functionality
- 🔗 **Referral Reward System** - Earn STX rewards by referring new users to the platform

## 🚀 Quick Start

### Prerequisites
- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- Node.js and npm for testing

### Installation
```bash
git clone https://github.com/AlheriGyang/Microgrid-Energy-Sharing-for-Rural-Communities
cd Microgrid-Energy-Sharing-for-Rural-Communities
clarinet check
npm install
```

## 📖 Usage

### 1️⃣ Register as User
```clarity
(contract-call? .contract register-user "Rural Village A" true none)
```
- `location`: Your community location (max 50 chars)
- `is-producer`: Set to `true` if you generate energy, `false` if consumer only
- `referrer`: Optional principal of the user who referred you (use `none` if no referrer)

### 2️⃣ Deposit Funds
```clarity
(contract-call? .contract deposit-funds u1000000)
```
Deposit STX tokens to your account balance for energy purchases.

### 3️⃣ List Energy for Sale (Producers Only)
```clarity
(contract-call? .contract list-energy u100 u50 "solar")
```
- `amount`: kWh to sell (100 kWh)
- `price-per-kwh`: Price in micro-STX (50 μSTX per kWh)
- `renewable-type`: "solar", "wind", "hydro", etc.

### 4️⃣ Buy Energy
```clarity
(contract-call? .contract buy-energy u1 u50)
```
- `listing-id`: ID of the energy listing
- `amount`: kWh to purchase (50 kWh)

### 5️⃣ Record Smart Meter Data
```clarity
(contract-call? .contract record-meter-reading u120 u80 u40)
```
- `energy-produced`: kWh produced this period
- `energy-consumed`: kWh consumed this period  
- `grid-contribution`: kWh contributed to community grid

## 🔍 Query Functions

### Get User Information
```clarity
(contract-call? .contract get-user-info 'SP1ABC...)
```

### Check Energy Listing
```clarity
(contract-call? .contract get-energy-listing u1)
```

### View Contract Statistics
```clarity
(contract-call? .contract get-contract-stats)
```

### Estimate Trade Cost
```clarity
(contract-call? .contract estimate-trade-cost u1 u25)
```

## 🔗 Referral Reward System

Earn STX rewards by bringing new users to the platform!

### Referring a New User
When registering, include your referrer's address:
```clarity
(contract-call? .contract register-user "Rural Village B" false (some 'SP1REFERRER...))
```

### Earning Rewards
- Receive 10 STX automatically when your referred user completes their first energy trade
- One-time reward per successful referral
- Builds community growth and engagement

## 🏗️ Contract Architecture

### Core Components
- **Users Map**: Stores user profiles, balances, energy statistics, and referral data
- **Energy Listings**: Available energy for sale with pricing
- **Trades**: Historical transaction records
- **Smart Meter Readings**: Time-stamped energy data

### Key Functions
- `register-user` - Join the energy sharing network
- `list-energy` - Put energy up for sale
- `buy-energy` - Purchase energy from other users
- `record-meter-reading` - Log smart meter data
- `deposit-funds`/`withdraw-funds` - Manage account balance

## 🔒 Security Features

- ✅ Input validation on all user data
- ✅ Authorization checks for sensitive operations
- ✅ Balance verification before trades
- ✅ Emergency pause functionality
- ✅ Reputation scoring system
- ✅ Protected admin functions

## 🧪 Testing

Run the test suite:
```bash
npm test
```

Check contract syntax:
```bash
clarinet check
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Run tests
5. Submit a pull request

## 📝 License

This project is open source and available under the MIT License.

## 🌍 Impact

Empowering rural communities with:
- 📉 Reduced energy costs through direct trading
- 🌿 Increased renewable energy adoption
- 💪 Energy independence and resilience
- 🤝 Stronger community cooperation
- 📊 Transparent energy marketplace
- 🔗 Viral user growth via referral incentives

---

Built with 💚 for sustainable energy access
