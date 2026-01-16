import {
    bool,
    byteString,
    conStr0,
    MeshTxBuilder,
    stringToHex,
    mConStr0,
    deserializeAddress,
    none,
    applyParamsToScript,
    PlutusScript,
    resolveScriptHash,
    IWallet,
    IFetcher,
    ISubmitter,
    IEvaluator,
} from "@meshsdk/core";
import { resolvePlutusScriptAddress } from "@meshsdk/core-cst";
import validatorsPlutusScript from "../onchain/aiken/plutus.json";

type IConfigOptions = {
    network: 0 | 1,
    wallet: IWallet,
    fetcher: IFetcher,
    submitter: ISubmitter,
    evaluator?: IEvaluator,
}
const test_admin_token_policy = "a8d770ae253e4818feb0a5f55dc29d85d86061feee7cc31347276322";
const test_admin_token_name = stringToHex("aidPod-admin");
const test_admin_token = {
    policy: test_admin_token_policy,
    name: test_admin_token_name
};

function patient_script(
    admin_token: { policy: string; name: string },
    hospital_auth_policy: string,
    network: 1 | 0
) {
    const cbor = validatorsPlutusScript.validators.find(
        ({ title }) => title === "patients.patient_campaign.spend"
    )?.compiledCode;
    if (!cbor) {
        throw new Error("Patient registry compiled code not found");
    }
    const appliedParams = applyParamsToScript(
        cbor,
        [
            conStr0([byteString(test_admin_token.policy), byteString(test_admin_token.name)]),
            byteString(hospital_auth_policy),
        ],
        "JSON"
    );
    const script: PlutusScript = {
        code: appliedParams,
        version: "V3",
    };
    const policyId = resolveScriptHash(appliedParams, "V3");
    const script_Address = resolvePlutusScriptAddress(script, network);
    return {
        policyid: policyId,
        script_address: script_Address,
        cbor: appliedParams,
    };
}

class Deploy {
    private network;
    constructor(network: 0 | 1) {
        this.network = network;
    }
    hospital_registry = async (admin_token: { policy: string; name: string }) => {
        const cbor = validatorsPlutusScript.validators.find(
            ({ title }) => title === "hospital.hospital_auth.mint"
        )?.compiledCode;
        if (!cbor) {
            throw new Error("Patient registry compiled code not found");
        }
        const appliedParams = applyParamsToScript(
            cbor,
            [conStr0([byteString(admin_token.policy), byteString(admin_token.name)])],
            "JSON"
        );
        const policyId = resolveScriptHash(appliedParams, "V3");
        return { hospital_policyid: policyId, cbor: appliedParams };
    };

    patient_registry = async (admin_token: { policy: string; name: string }) => {
        const { hospital_policyid } = await this.hospital_registry(admin_token);
        console.log("hospital_policyid", hospital_policyid);
        const { policyid, cbor, script_address } = patient_script(
            admin_token,
            hospital_policyid,
            this.network
        );
        return { policyid, cbor, script_address };
    };

    hospital_claim = async (admin_token: { policy: string; name: string }) => {
        const { hospital_policyid } = await this.hospital_registry(admin_token);
        const { script_address, cbor } = patient_script(
            admin_token,
            hospital_policyid,
            this.network
        );
        return { script_address, cbor };
    };
}

export class medicalCrowdfundingContract {
    private configOptions: IConfigOptions;
    constructor(configOptions: IConfigOptions) {
        this.configOptions = configOptions;
    }
    async createCampaign(
        hospitalName: string,
        initialFunding: string = "2000000" // 2 ADA minimum
    ) {
        const changeAddress = await this.configOptions.wallet.getChangeAddress();
        const utxos = await this.configOptions.wallet.getUtxos();

        const script = new Deploy(this.configOptions.network);
        const { script_address } = await script.patient_registry(test_admin_token);

        const hospitalTokenName = hospitalName + "HOSPITAL";
        const hospitalTokenNameHex = stringToHex(hospitalTokenName);
        const campaignDatum = conStr0([byteString(hospitalTokenNameHex), bool(true)]);

        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            submitter: this.configOptions.submitter,
        });

        const unsignedTx = await txBuilder
            .txOut(script_address, [{ unit: "lovelace", quantity: initialFunding }])
            .txOutInlineDatumValue(campaignDatum, "JSON")
            .changeAddress(changeAddress)
            .selectUtxosFrom(utxos)
            .complete();

        const signedTx = await this.configOptions.wallet.signTx(unsignedTx);
        const txHash = await this.configOptions.wallet.submitTx(signedTx);

        return {
            txHash,
            campaignAddress: script_address,
            authorizedHospital: hospitalName,
            campaignActive: true,
            initialFunding,
        };
    }

    async donateToCampaign(donationAmount: string) {
        const changeAddress = await this.configOptions.wallet.getChangeAddress();
        const utxos = await this.configOptions.wallet.getUtxos();
        const collateral = (await this.configOptions.wallet.getCollateral())[0];
        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            submitter: this.configOptions.submitter,
        });
        const script = new Deploy(this.configOptions.network);
        const { script_address } = await script.patient_registry(test_admin_token);

        const unsignedTx = await txBuilder
            .txOut(script_address, [{ unit: "lovelace", quantity: donationAmount }])
            .txOutInlineDatumValue(conStr0([none()]), "JSON")

            .changeAddress(changeAddress)
            .selectUtxosFrom(utxos)
            .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
            .complete();

        const signedTx = await this.configOptions.wallet.signTx(unsignedTx);
        const txHash = await this.configOptions.wallet.submitTx(signedTx);

        console.log("Donation successful!");

        return {
            txHash,
            donationAmount,
            campaignAddress: script_address,
        };
    }

    async claimCampaignFunds(
        campaignTxHash: string,
        hospitalName: string
    ) {
        const changeAddress = await this.configOptions.wallet.getChangeAddress();
        const utxos = await this.configOptions.wallet.getUtxos();
        const collateral = (await this.configOptions.wallet.getCollateral())[0];

        const script = new Deploy(this.configOptions.network);
        const { cbor: campaign_cbor } = await script.hospital_claim(test_admin_token);
        const { hospital_policyid } = await script.hospital_registry(test_admin_token);

        const hospitalTokenName = stringToHex(hospitalName + "HOSPITAL");
        const hospitalAsset = hospital_policyid + hospitalTokenName;

        console.log("Finding hospital UTxO with token:", hospitalAsset);

        const hospitalUtxo = utxos.find((utxo) =>
            utxo.output.amount.some((a) => a.unit === hospitalAsset)
        );

        if (!hospitalUtxo) {
            throw new Error(`Hospital auth token not found: ${hospitalAsset}`);
        }
        const campaignUtxos = await this.configOptions.fetcher.fetchUTxOs(campaignTxHash);
        if (campaignUtxos.length === 0) {
            throw new Error("Campaign UTxO not found");
        }

        const campaignUtxo = campaignUtxos[0];

        const campaignScriptAddress = campaignUtxo.output.address;
        const campaignScriptUtxos = await this.configOptions.fetcher.fetchAddressUTxOs(
            campaignScriptAddress
        );
        const markerUtxo = campaignScriptUtxos.find(
            (utxo) => utxo.output.plutusData !== undefined
        );

        if (!markerUtxo) {
            throw new Error("Campaign marker UTxO not found");
        }

        const redeemer = mConStr0([]);
        const { pubKeyHash } = deserializeAddress(changeAddress);

        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            evaluator: this.configOptions.evaluator,
            submitter: this.configOptions.submitter,
        });

        const unsignedTx = await txBuilder
            .spendingPlutusScriptV3()
            .txIn(markerUtxo.input.txHash, markerUtxo.input.outputIndex)
            .spendingReferenceTxInInlineDatumPresent()
            .spendingReferenceTxInRedeemerValue(redeemer)
            .txInScript(campaign_cbor)

            .spendingPlutusScriptV3()
            .txIn(campaignUtxo.input.txHash, campaignUtxo.input.outputIndex)
            .spendingReferenceTxInInlineDatumPresent()
            .spendingReferenceTxInRedeemerValue(redeemer)
            .txInScript(campaign_cbor)

            .txIn(hospitalUtxo.input.txHash, hospitalUtxo.input.outputIndex)
            .requiredSignerHash(pubKeyHash)

            .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
            .changeAddress(changeAddress)
            .selectUtxosFrom(utxos)
            .complete();

        const signedTx = await this.configOptions.wallet.signTx(unsignedTx);
        const txHash = await this.configOptions.wallet.submitTx(signedTx);

        return txHash;
    }

    async registerHospital(hospitalName: string) {
        const changeAddress = await this.configOptions.wallet.getChangeAddress();
        const utxos = await this.configOptions.wallet.getUtxos();
        const collateral = (await this.configOptions.wallet.getCollateral())[0];

        const script = new Deploy(this.configOptions.network);
        const { hospital_policyid, cbor } =
            await script.hospital_registry(test_admin_token);
        const tokenName = stringToHex(hospitalName + "HOSPITAL");
        const asset = hospital_policyid + tokenName;
        const hospitalNameHex = stringToHex(hospitalName);
        const redeemer = mConStr0([hospitalNameHex]);
        const adminUtxo = utxos.find((utxo) =>
            utxo.output.amount.some(
                (a) => a.unit === test_admin_token.policy + test_admin_token.name
            )
        );

        if (!adminUtxo) {
            throw new Error(
                `Admin token not found in wallet. Required: ${test_admin_token.policy}${test_admin_token.name}`
            );
        }

        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            submitter: this.configOptions.submitter,
            evaluator: this.configOptions.evaluator,
        });

        const unsignedTx = await txBuilder
            .txIn(adminUtxo.input.txHash, adminUtxo.input.outputIndex)
            .mintPlutusScriptV3()
            .mint("1", hospital_policyid, tokenName)
            .mintingScript(cbor)
            .mintRedeemerValue(redeemer, "Mesh")
            .txOut(changeAddress, [{ unit: asset, quantity: "1" }])
            .changeAddress(changeAddress)
            .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
            .selectUtxosFrom(utxos)
            .complete();
        return {
            unsignedTx,
        }
    }

    async registerPatient(patientName: string, wallet: IWallet) {
        const changeAddress = await wallet?.getChangeAddress();
        const utxos = await wallet?.getUtxos();
        const collateral = (await wallet?.getCollateral())[0];

        const script = new Deploy(0);
        const { policyid, cbor } = await script.patient_registry(test_admin_token);

        const tokenName = stringToHex(patientName + "PATIENT");
        const asset = policyid + tokenName;
        const patientNameHex = stringToHex(patientName);
        const redeemer = mConStr0([patientNameHex]);
        const adminUtxo = utxos.find((utxo) =>
            utxo.output.amount.some(
                (a) => a.unit === test_admin_token.policy + test_admin_token.name
            )
        );

        if (!adminUtxo) {
            throw new Error(
                `Admin token not found in wallet. Required: ${test_admin_token.policy}${test_admin_token.name}`
            );
        }

        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            submitter: this.configOptions.submitter,
            evaluator: this.configOptions.evaluator,
        });

        const unsignedTx = await txBuilder
            .txIn(adminUtxo.input.txHash, adminUtxo.input.outputIndex)
            .mintPlutusScriptV3()
            .mint("1", policyid, tokenName)
            .mintingScript(cbor)
            .mintRedeemerValue(redeemer, "Mesh")
            .txOut(changeAddress, [{ unit: asset, quantity: "1" }])
            .changeAddress(changeAddress)
            .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
            .selectUtxosFrom(utxos)

            .complete();
        const signedTx = await this.configOptions.wallet.signTx(unsignedTx);
        const txHash = await this.configOptions.wallet.submitTx(signedTx);
        return {
            txHash
        };
    }

    // burnHospitalToken from unlist/unlisthospital.ts
    async burnHospitalToken(hospitalName: string) {
        const changeAddress = await this.configOptions.wallet.getChangeAddress();
        const utxos = await this.configOptions.wallet.getUtxos();
        const collateral = (await this.configOptions.wallet.getCollateral())[0];

        const script = new Deploy(0);
        const { hospital_policyid, cbor } = await script.hospital_registry(test_admin_token);

        const tokenName = stringToHex(hospitalName + "HOSPITAL");
        const asset = hospital_policyid + tokenName;

        // Find UTxO with the hospital token to burn
        const tokenUtxo = utxos.find((utxo) =>
            utxo.output.amount.some((a) => a.unit === asset)
        );

        if (!tokenUtxo) {
            throw new Error(`Hospital token not found: ${asset}`);
        }

        // BurnAuth redeemer (no parameters)
        const redeemer = mConStr0([]);

        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            submitter: this.configOptions.submitter,
            evaluator: this.configOptions.evaluator,
        });

        const unsignedTx = await txBuilder
            .mintPlutusScriptV3()
            .mint("-1", hospital_policyid, tokenName)
            .mintingScript(cbor)
            .mintRedeemerValue(redeemer, "Mesh")

            .txIn(
                tokenUtxo.input.txHash,
                tokenUtxo.input.outputIndex
            )

            .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
            .changeAddress(changeAddress)
            .selectUtxosFrom(utxos)
            .complete();

        const signedTx = await this.configOptions.wallet.signTx(unsignedTx);
        const txHash = await this.configOptions.wallet.submitTx(signedTx);

        console.log("Hospital token burned successfully!");
        console.log("Transaction hash:", txHash);

        return txHash;
    }

    // burnPatientToken from unlist/unlistPatient.ts
    async burnPatientToken(patientName: string) {
        const changeAddress = await this.configOptions.wallet.getChangeAddress();
        const utxos = await this.configOptions.wallet.getUtxos();
        const collateral = (await this.configOptions.wallet.getCollateral())[0];

        const script = new Deploy(0);
        const { policyid, cbor } = await script.patient_registry(test_admin_token);

        const tokenName = stringToHex(patientName + "PATIENT");
        const asset = policyid + tokenName;

        const tokenUtxo = utxos.find((utxo) =>
            utxo.output.amount.some((a) => a.unit === asset)
        );

        if (!tokenUtxo) {
            throw new Error(`Patient token not found: ${asset}`);
        }

        const redeemer = mConStr0([]);

        const txBuilder = new MeshTxBuilder({
            fetcher: this.configOptions.fetcher,
            submitter: this.configOptions.submitter,
            evaluator: this.configOptions.evaluator,
        });

        const unsignedTx = await txBuilder
            .mintPlutusScriptV3()
            .mint("-1", policyid, tokenName)
            .mintingScript(cbor)
            .mintRedeemerValue(redeemer, "Mesh")

            .txIn(
                tokenUtxo.input.txHash,
                tokenUtxo.input.outputIndex
            )

            .txInCollateral(collateral.input.txHash, collateral.input.outputIndex)
            .changeAddress(changeAddress)
            .selectUtxosFrom(utxos)
            .complete();

        const signedTx = await this.configOptions.wallet.signTx(unsignedTx);
        const txHash = await this.configOptions.wallet.submitTx(signedTx);

        return txHash;
    }
}
