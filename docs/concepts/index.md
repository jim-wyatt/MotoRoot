# Android internals

The [preparation walkthrough](../device/walkthrough.md) assumes you already know what a partition is, why slot A matters, and what "LK" stands for. These pages fill in that background, so that when you run a command you know what it is doing and what would happen if it went wrong. They're also just a good tour of how Android is built, useful well beyond this one device.

Read them in order the first time; each builds on the one before.

| Page | Question it answers |
| --- | --- |
| [ADB and Fastboot](adb-and-fastboot.md) | What are the two tools for talking to the device, and when do I use which? |
| [Partitions and A/B slots](partitions-and-slots.md) | Where does Android live on the device's storage, and why are there two copies? |
| [The boot chain](boot-chain.md) | What happens between the power button and the home screen, and what does unlocking change? |
| [System-level access](system-access.md) | What does `uid=0` mean, why do dev devices need it, and how do the pieces here provide it? |
| [System modules with Magisk](magisk-modules.md) | How do you change system behavior without editing the read-only system image? |
| [Device provisioning](device-provisioning.md) | How does initial device setup work, and what is Test DPC? |

## The mental model in one paragraph

An Android device is a small Linux computer. Its storage is divided into **partitions**: a few hold the pieces that start the system (the **boot chain**), most hold Android itself, and a handful hold data unique to your unit. The chip's first-stage code only runs a bootloader it trusts, the bootloader only runs a kernel it trusts, and so on down the chain. A **locked** bootloader enforces that chain and runs only the factory build; **unlocking** it — the vendor-supported `fastboot oem unlock` — lets the device run builds and code you supply, which is what makes it a development device. **Root** (`uid 0`) is the privileged Linux user that an emulator gives you for free; on hardware you obtain it through **Magisk**, which inserts itself into the boot chain. Magisk **modules** overlay changes on top of the system instead of editing it, so everything stays reversible.

Every step in the preparation procedure is one move in that picture. These pages show you which.
