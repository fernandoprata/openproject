// Declare some globals
// to work around previously magical global constants
// provided by typings@global

// Active issue
// https://github.com/Microsoft/TypeScript/issues/10178

/// <reference path="../../node_modules/@types/mocha/index.d.ts" />
/// <reference path="../../node_modules/@types/angular-mocks/index.d.ts" />
/// <reference path="../../node_modules/@types/chai/index.d.ts" />
/// <reference path="../../node_modules/@types/chai-as-promised/index.d.ts" />
/// <reference path="../../node_modules/@types/sinon/index.d.ts" />
/// <reference path="../../node_modules/@types/sinon-chai/index.d.ts" />
/// <reference path="../../node_modules/@types/jquery/index.d.ts" />
/// <reference path="../../node_modules/@types/jqueryui/index.d.ts" />
/// <reference path="../../node_modules/@types/mousetrap/index.d.ts" />
/// <reference path="../../node_modules/@types/moment-timezone/index.d.ts" />
/// <reference path="../../node_modules/@types/urijs/index.d.ts" />
/// <reference path="../../node_modules/@types/webpack-env/index.d.ts" />
/// <reference path="../../node_modules/@types/es6-shim/index.d.ts" />

import {Injector} from '@angular/core';
import * as TAngular from 'angular';
import {OpenProject} from 'core-app/globals/openproject';
import * as TLodash from 'lodash';
import * as TMoment from 'moment';
import * as TSinon from 'sinon';
import {GlobalI18n} from "core-app/modules/common/i18n/i18n.service";

declare global {
  const _:typeof TLodash;
  const angular:typeof TAngular;
  const sinon:typeof TSinon;
  const moment:typeof TMoment;
  const bowser:any;
  const I18n:GlobalI18n;

  declare const require:any;
  declare const describe:any;
  declare const beforeEach:any;
  declare const afterEach:any;
  declare const after:any;
  declare const before:any;
  declare const it:(desc:string, callback:(done:() => void) => void) => void;

}

declare global {
  interface Window {
    appBasePath:string;
    ng2Injector:Injector;
    OpenProject:OpenProject;
  }

  interface JQuery {
    topShelf:any;
    atwho:any;
    mark:any;
  }
}

export {};
