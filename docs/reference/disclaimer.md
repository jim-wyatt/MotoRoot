# Disclaimer

**Read this before using anything in this project.** By using the software, scripts, modules, documentation or instructions here (together, "the Project"), you accept the terms below. If you do not accept them, do not use the Project. This page is the same text as [`DISCLAIMER.md`](https://github.com/jim-wyatt/OtomDev/blob/main/DISCLAIMER.md) in the repository.

## No warranty

The Project is provided **"as is"**, without warranty of any kind, express or implied, including but not limited to the warranties of merchantability, fitness for a particular purpose and non-infringement, as stated in the [MIT License](https://github.com/jim-wyatt/OtomDev/blob/main/LICENSE). Nothing in the documentation is a promise that any step will work on your device, or will not harm it.

## You assume all risk

Modifying a device's bootloader, boot images or system configuration can:

- permanently render the device unbootable ("bricked"), with no recovery method known to the Project;
- erase all data on the device;
- void the manufacturer's or seller's warranty and make the device ineligible for support or repair;
- weaken the device's security, including by keeping it on firmware with known vulnerabilities and by giving software root access;
- cause apps and services that check device integrity (banking, payment, streaming, games, enterprise tools) to refuse to run;
- interfere with cellular, SIM, voicemail, emergency-call or carrier features, in particular after the optional carrier debloat.

You accept these risks in full. To the fullest extent permitted by law, the authors and contributors of the Project are not liable for any damage to or loss of a device, data, warranty coverage, money, time or anything else arising from use of, or inability to use, the Project, however caused and under any theory of liability.

## Devices you own, and the law

Use the Project only on a device that **you own outright** and are legally entitled to modify, or on which you have the owner's explicit authorization.

- Do not use it on a device that is leased, financed, rented, employer- or school-owned, subject to a payment plan, a device-lock or "financed device" programme, or otherwise not fully yours. Parts of the procedure disable Android's device-lock controller and hide carrier and financing components. Those steps exist to leave an unencumbered, Wi-Fi-only device unmanaged; they must not be used to evade a financing, lease, subsidy or carrier obligation.
- The Project does not provide, and is not intended for, bypassing SIM or network locks, account locks such as Factory Reset Protection, DRM, payment or integrity systems, or any other protection that is not yours to remove. It installs no root-hiding or integrity-bypass software.
- You are responsible for complying with all laws, regulations, carrier agreements, terms of service and warranties that apply to you and your device in your jurisdiction, and for the consequences of not doing so. The Project does not tell you what those are.

## Scope of what was tested

The procedure was carried out on **two units** of one model, **XT2617V**, on one firmware build, on the dates recorded in the [validation notes](../device/validation.md). Two successful runs are not a guarantee of a third. A tool reporting success, a verifier reporting `VALID`, or a hash matching, is not evidence that your device will behave the same way. Other models, variants, firmware builds, security patches or kernels are untested and may be unsafe. Future manufacturer updates may close the paths the procedure uses or change the device's behaviour, and the Project may not be updated to reflect that.

## Third-party software

The Project downloads and uses software published by others, including Google, Motorola and the authors of Magisk, KernelSU, DFRoot, Val Protocol and Test DPC, as well as development tools; see [`NOTICE.md`](https://github.com/jim-wyatt/OtomDev/blob/main/NOTICE.md) and the [credits](credits.md). That software is governed by its own licenses and terms, is not part of the Project, is not endorsed by or affiliated with the Project, and may change or disappear. The Project verifies downloads against recorded hashes but makes no claim about the third-party software's safety, correctness or legality, and you obtain and use it at your own risk and under its terms.

## No affiliation

The Project is an independent, personal engineering project. It is not affiliated with, endorsed by, sponsored by or supported by Motorola Mobility LLC, Lenovo, Google LLC, Verizon, TracFone Wireless, Straight Talk, Walmart, MediaTek, or any carrier, manufacturer, retailer or software author named in it. All product names, logos and brands are the property of their respective owners and are used for identification only.

## Not professional advice

Nothing in the Project is legal, security, financial or professional engineering advice. If you are unsure whether you may modify a device, or what the consequences would be, consult the device's owner, the seller, the carrier or a qualified professional before proceeding.

## Changes

The Project may change this disclaimer at any time by updating the repository file. The version in the repository at the time you use the Project applies.
