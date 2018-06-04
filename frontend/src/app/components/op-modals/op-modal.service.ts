import {ApplicationRef, ComponentFactoryResolver, ComponentRef, Injectable, Injector} from '@angular/core';
import {ComponentPortal, ComponentType, DomPortalOutlet, PortalInjector} from '@angular/cdk/portal';
import {TransitionService} from '@uirouter/core';
import {OpModalLocalsToken} from 'core-app/angular4-transition-utils';
import {OpModalComponent} from 'core-components/op-modals/op-modal.component';
import {keyCodes} from 'core-app/modules/common/keyCodes.enum';
import {FocusHelperService} from 'core-app/modules/common/focus/focus-helper';

@Injectable()
export class OpModalService {
  public active:OpModalComponent|null = null;

  // Hold a reference to the DOM node we're using as a host
  private portalHostElement:HTMLElement;
  // And a reference to the actual portal host interface on top of the element
  private bodyPortalHost:DomPortalOutlet;

  // Remember when we're opening a new modal to avoid the outside click bubbling up.
  private opening:boolean = false;

  constructor(private componentFactoryResolver:ComponentFactoryResolver,
              readonly FocusHelper:FocusHelperService,
              private appRef:ApplicationRef,
              private $transitions:TransitionService,
              private injector:Injector) {

    const hostElement = this.portalHostElement = document.createElement('div');
    hostElement.classList.add('op-modals--overlay');
    document.body.appendChild(hostElement);

    // Listen to keyups on window to close context menus
    jQuery(window).keydown('keydown', (evt:JQueryKeyEventObject) => {
      if (this.active && this.active.closeOnEscape && evt.which === keyCodes.ESCAPE) {
        this.close(evt);
      }

      return true;
    });

    // Listen to any click when should close outside modal
    jQuery(window).click((evt) => {
      if (this.active &&
        !this.opening &&
        this.active.closeOnOutsideClick &&
        !this.portalHostElement.contains(evt.target)) {
        this.close(evt);
      }
    });

    this.bodyPortalHost = new DomPortalOutlet(
      hostElement,
      this.componentFactoryResolver,
      this.appRef,
      this.injector
    );
  }

  /**
   * Open a Modal reference and append it to the portal
   */
  public show<T extends OpModalComponent>(modal:ComponentType<T>, locals:any = {}, injector:Injector = this.injector):T {
    this.close();

    // Prevent closing events during the opening time frame.
    this.opening = true;

    // Create a portal for the given component class and render it
    const portal = new ComponentPortal(modal, null, this.injectorFor(injector, locals));
    const ref:ComponentRef<OpModalComponent> = this.bodyPortalHost.attach(portal) as ComponentRef<OpModalComponent>;
    const instance = ref.instance as T;
    this.active = instance;
    this.portalHostElement.style.display = 'block';

    setTimeout(() => {
      // Focus on the first element
      this.active && this.active.onOpen(this.activeModal);

      // Mark that we've opened the modal now
      this.opening = false;
    }, 20);

    return this.active as T;
  }

  public isActive(modal:OpModalComponent) {
    return this.active && this.active === modal;
  }

  /**
   * Closes currently open modal window
   */
  public close(evt?:Event) {
    // Detach any component currently in the portal
    if (this.active && this.active.onClose()) {
      this.active.closingEvent.emit(this.active);
      this.bodyPortalHost.detach();
      this.portalHostElement.style.display = 'none';
      this.active = null;

      if (evt) {
        evt.preventDefault();
        evt.stopPropagation();
      }
    }
  }

  public get activeModal():JQuery {
    return jQuery(this.portalHostElement).find('.op-modal--portal');
  }

  /**
   * Create an augmented injector that is equal to this service's injector + the additional data
   * passed into +show+.
   * This allows callers to pass data into the newly created modal.
   *
   */
  private injectorFor(injector:Injector, data:any) {
    const injectorTokens = new WeakMap();
    // Pass the service because otherwise we're getting a cyclic dependency between the portal
    // host service and the bound portal
    data.service = this;

    injectorTokens.set(OpModalLocalsToken, data);

    return new PortalInjector(injector, injectorTokens);
  }
}
