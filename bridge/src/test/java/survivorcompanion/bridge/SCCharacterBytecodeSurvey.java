// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;

import java.io.InputStream;
import java.lang.classfile.ClassFile;
import java.lang.classfile.ClassModel;
import java.lang.classfile.CodeElement;
import java.lang.classfile.Instruction;
import java.lang.classfile.MethodModel;
import java.lang.classfile.instruction.FieldInstruction;
import java.lang.classfile.instruction.InvokeInstruction;
import java.util.Set;

/** Research-only call/field trace for selected version-pinned character methods. */
public final class SCCharacterBytecodeSurvey {
    private SCCharacterBytecodeSurvey() {}

    private static void trace(String className, Set<String> names) throws Exception {
        String resource = "/" + className.replace('.', '/') + ".class";
        byte[] bytes;
        try (InputStream stream = SCCharacterBytecodeSurvey.class.getResourceAsStream(resource)) {
            if (stream == null) throw new IllegalStateException("missing " + resource);
            bytes = stream.readAllBytes();
        }
        ClassModel model = ClassFile.of().parse(bytes);
        for (MethodModel method : model.methods()) {
            String name = method.methodName().stringValue();
            if (!names.contains(name)) continue;
            System.out.println("METHOD " + className + "." + name
                    + method.methodType().stringValue());
            if (method.code().isEmpty()) continue;
            int index = 0;
            for (CodeElement element : method.code().get()) {
                if (!(element instanceof Instruction instruction)) continue;
                if (instruction instanceof InvokeInstruction invoke) {
                    System.out.println("  " + index + " " + instruction.opcode() + " CALL "
                            + invoke.owner().asInternalName() + "." + invoke.name().stringValue()
                            + invoke.type().stringValue());
                } else if (instruction instanceof FieldInstruction field) {
                    System.out.println("  " + index + " " + instruction.opcode() + " FIELD "
                            + field.owner().asInternalName() + "." + field.name().stringValue()
                            + ":" + field.type().stringValue());
                }
                index++;
            }
        }
    }

    private static void traceDetailed(String className, Set<String> names) throws Exception {
        String resource = "/" + className.replace('.', '/') + ".class";
        byte[] bytes;
        try (InputStream stream = SCCharacterBytecodeSurvey.class.getResourceAsStream(resource)) {
            if (stream == null) throw new IllegalStateException("missing " + resource);
            bytes = stream.readAllBytes();
        }
        ClassModel model = ClassFile.of().parse(bytes);
        for (MethodModel method : model.methods()) {
            String name = method.methodName().stringValue();
            if (!names.contains(name)) continue;
            System.out.println("DETAIL " + className + "." + name
                    + method.methodType().stringValue());
            if (method.code().isEmpty()) continue;
            int index = 0;
            for (CodeElement element : method.code().get()) {
                System.out.println("  " + index++ + " " + element);
            }
        }
    }

    public static void main(String[] args) throws Exception {
        trace("zombie.characters.IsoPlayer", Set.of(
                "<init>", "InitSpriteParts", "addToWorld", "render",
                "setAddedToModelManager", "syncVisuals", "setIsAiming", "isAiming",
                "nullifyAiming", "updateMovementRates"));
        trace("zombie.characters.IsoGameCharacter", Set.of(
                "<init>", "InitSpriteParts", "initSpritePartsEmpty", "Dressup",
                "addToWorld", "updateInternal", "updateModelSlot", "setAddedToModelManager",
                "setSceneCulled", "Say", "ProcessSay", "addLineChatElement", "renderlast", "render"));
        trace("zombie.characters.IsoLivingCharacter", Set.of("setIsAiming", "isAiming"));
        trace("zombie.core.skinnedmodel.ModelManager", Set.of(
                "Add", "Remove", "addNewSlot"));
        traceDetailed("zombie.characters.IsoGameCharacter", Set.of(
                "setSceneCulled", "addToWorld", "removeFromWorld"));
        traceDetailed("zombie.iso.IsoMovingObject", Set.of(
                "setSceneCulled", "addToWorld", "removeFromWorld", "removeFromSquare"));
        traceDetailed("zombie.core.skinnedmodel.ModelManager", Set.of("Add", "Remove"));
    }
}
