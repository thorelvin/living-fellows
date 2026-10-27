// SPDX-License-Identifier: MIT
package survivorcompanion.bridge;
import zombie.IndieGL;
import zombie.core.textures.Texture;
import zombie.ui.UIElement;
public final class SCTerminalLogoRendererTest {
    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
    private static boolean draw(UIElement host, double x, double width, double red) {
        return SCTerminalLogoRenderer.draw(host,new Texture(),x,2,width,90,.78,
                red,.9,.85,1,1,1,true,false,false);
    }
    public static void main(String[] args) throws Exception {
        int[] draws={0};
        UIElement host=new UIElement() {
            @Override public void DrawTextureScaledColor(Texture texture,Double x,Double y,Double w,Double h,
                    Double r,Double g,Double b,Double a) {
                draws[0]++;
                require(r==1 && g==1 && b==1 && a==.78,"native vertex tint changed shader colours");
                require(!draw(this,0,210,.5),"nested draw entered another shader scope");
            }
        };
        require(draw(host,0,210,.7) && draws[0]==1,"scoped UI draw failed");
        require(IndieGL.testPushes==1 && IndieGL.testPops==1,"ordinary draw leaked shader state");
        UIElement throwing=new UIElement() {
            @Override public void DrawTextureScaledColor(Texture texture,Double x,Double y,Double w,Double h,
                    Double r,Double g,Double b,Double a) { throw new IllegalStateException("test UI failure"); }
        };
        try { draw(throwing,0,210,.7); throw new AssertionError("draw failure was swallowed"); }
        catch (IllegalStateException expected) { }
        require(IndieGL.testPushes==2 && IndieGL.testPops==2,"failed draw leaked shader state");
        require(draw(host,0,210,.7),"draw after exception remained stuck");
        int pushes=IndieGL.testPushes;
        require(!draw(null,0,210,.7) && !draw(host,Double.NaN,210,.7)
                && !draw(host,0,0,.7) && !draw(host,0,Double.POSITIVE_INFINITY,.7)
                && !draw(host,0,210,-.1),"invalid UI input reached rendering");
        boolean[] foreign={true};
        Thread thread=new Thread(()->foreign[0]=draw(host,0,210,.7));
        thread.start(); thread.join();
        require(!foreign[0] && IndieGL.testPushes==pushes,"another thread entered the UI shader scope");
        require(IndieGL.testPushes==IndieGL.testPops,"shader stack is unbalanced");
        System.out.println("TERMINAL_LOGO_RENDERER_PASS scoped=true nested=true errors=true thread=true input=true");
    }
}
